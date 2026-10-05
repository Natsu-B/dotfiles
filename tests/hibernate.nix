{ pkgs, config }:
let
  facts = pkgs.writeText "dotfiles-s4-policy.json" (builtins.toJSON {
    swap = map (s: { inherit (s) device size; encrypted = s.randomEncryption.enable; }) config.swapDevices;
    initrdSystemd = config.boot.initrd.systemd.enable;
    efi = config.boot.initrd.systemd.package.withEfi;
    resumeDevice = config.boot.resumeDevice;
    kernelParams = config.boot.kernelParams;
    sleep = config.systemd.sleep.settings.Sleep;
    logind = config.services.logind.settings.Login;
    strategy = config.systemd.services.systemd-suspend.overrideStrategy;
    unit = config.systemd.units."systemd-suspend.service".text;
    failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
  });
in
pkgs.runCommand "dotfiles-s4-policy-check" { nativeBuildInputs = [ pkgs.python3 pkgs.shellcheck ]; } ''
  shellcheck ${../scripts/stage-s4.sh}
  test -x ${config.boot.initrd.systemd.package}/lib/systemd/system-generators/systemd-hibernate-resume-generator
  test -x ${config.boot.initrd.systemd.package}/lib/systemd/systemd-hibernate-resume
  python3 - ${facts} <<'PY'
  import json, sys
  facts = json.load(open(sys.argv[1]))
  assert not facts['failedAssertions'], facts['failedAssertions']
  assert facts['initrdSystemd'] and facts['efi']
  assert facts['resumeDevice'] == ""
  assert not any(p.startswith(('resume=', 'resume_offset=')) for p in facts['kernelParams'])
  swap = next(s for s in facts['swap'] if s['device'] == '/var/lib/hibernate.swap')
  assert swap['size'] >= 40 * 1024 and not swap['encrypted']
  assert facts['sleep']['AllowHibernation'] and facts['sleep']['HibernateMode'] == 'platform'
  assert 'SuspendState' not in facts['sleep'] # disk here skips hibernate preparation
  for key in ['SleepOperation', 'HandleSuspendKey', 'HandleHibernateKey',
              'HandleLidSwitch', 'HandleLidSwitchExternalPower']:
      assert facts['logind'][key] == 'hibernate', key
  assert facts['logind']['HandleLidSwitchDocked'] == 'ignore'
  assert facts['strategy'] == 'asDropin' # retain the vendor unit's dependencies
  starts = [line for line in facts['unit'].splitlines() if line.startswith('ExecStart=')]
  assert len(starts) == 2 and starts[0] == 'ExecStart=', starts
  assert starts[1].endswith('/lib/systemd/systemd-sleep hibernate'), starts
  print('S4: persistent swap, EFI resume, sleep/lid actions and ExecStart reset verified')
  PY
  touch "$out"
''
