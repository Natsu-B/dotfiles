{ ... }: {
  # USB JTAG cable access for the plugdev group (already granted to hotaru).
  # No world-writable USB nodes; keep this scoped to known cable device IDs.
  services.udev.extraRules = ''
    # Digilent USB JTAG (FTDI FT2232H, e.g. Basys 3)
    SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    # Xilinx Platform Cable USB II
    SUBSYSTEM=="usb", ATTR{idVendor}=="03fd", ATTR{idProduct}=="0008", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="03fd", ATTR{idProduct}=="0013", MODE="0660", GROUP="plugdev", TAG+="uaccess"
  '';
}
