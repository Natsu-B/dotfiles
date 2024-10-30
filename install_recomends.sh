#!bin/bash

# discord
sudo snap install discord

# slack
sudo snap install slack

# notion
sudo snap install notion-snap-reborn

# qemu aarch64
sudo apt install -y build-essential bison bc flex gcc-aarch64-linux-gnu libssl-dev make qemu-system-arm curl git qemu-efi-aarch64

# install rust aarch64
curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"
rustup target add aarch64-unknown-none
rustup component add rust-src

cargo install xremap --features gnome   # GNOME Wayland
# run without sudo
sudo gpasswd -a $USER input
echo 'KERNEL=="uinput", GROUP="input", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/input.rules