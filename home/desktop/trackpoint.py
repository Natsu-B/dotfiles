"""Keep a brief middle-button release inside the same TrackPoint scroll gesture."""
import argparse
from contextlib import closing
import select
import time

EV_KEY, EV_REL, BTN_MIDDLE = 1, 2, 274


class ReleaseGrace:
    def __init__(self, seconds=0.12):
        self.seconds = seconds
        self.down = False
        self.moved = False
        self.deadline = None

    def expire(self, now):
        if self.deadline is None or now < self.deadline:
            return []
        self.deadline = None
        self.down = self.moved = False
        return [(EV_KEY, BTN_MIDDLE, 0)]

    def feed(self, event, now):
        output = self.expire(now)
        kind, code, value = event
        if kind == EV_KEY and code == BTN_MIDDLE:
            if value == 1:
                if self.down:
                    self.deadline = None
                    return output
                self.down = True
                self.moved = False
            elif value == 0:
                if not self.down:
                    return output
                if self.moved:
                    if self.deadline is None:
                        self.deadline = now + self.seconds
                    return output
                self.down = False
        elif kind == EV_REL and code in (0, 1) and value and self.down:
            self.moved = True
        output.append(event)
        return output


def main():
    from evdev import InputDevice, UInput, ecodes

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default='/dev/input/by-path/platform-i8042-serio-1-event-mouse')
    parser.add_argument('--release-grace-ms', type=int, default=120)
    args = parser.parse_args()
    if not 1 <= args.release_grace_ms <= 500:
        parser.error('release grace must be between 1 and 500 milliseconds')

    with closing(InputDevice(args.device)) as device:
        if device.name != 'TPPS/2 Elan TrackPoint':
            raise RuntimeError('Refusing to filter a different input device')
        if device.active_keys():
            raise RuntimeError('TrackPoint buttons are held; retry after release')
        info = device.info
        # Keep the native pointing-stick properties, quirks and device settings.
        with UInput.from_device(device, name=device.name, phys='dotfiles/trackpoint',
                                input_props=device.input_props(), bustype=info.bustype,
                                vendor=info.vendor, product=info.product, version=info.version) as output:
            with device.grab_context():
                grace = ReleaseGrace(args.release_grace_ms / 1000)
                while True:
                    timeout = None if grace.deadline is None else max(0, grace.deadline - time.monotonic())
                    if select.select([device], [], [], timeout)[0]:
                        for event in device.read():
                            if event.type == ecodes.EV_SYN and event.code == ecodes.SYN_DROPPED:
                                # Restart instead of retaining an unknown button state.
                                raise RuntimeError('Input queue overflow; reconnecting TrackPoint')
                            for forwarded in grace.feed((event.type, event.code, event.value), time.monotonic()):
                                output.write(*forwarded)
                    else:
                        for forwarded in grace.expire(time.monotonic()):
                            output.write(*forwarded)
                        output.syn()


if __name__ == '__main__':
    main()
