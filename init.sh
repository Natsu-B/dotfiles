#!/bin/bash
<< "NoUninstall"
echo "Warning!!!"
echo "This scrpit is expected to run under CUI enviroment!!!"
echo "If you want to run Ubuntu Desktop. Change language to English."
echo "Then restart and at the GUI login screen press Ctrl + Alt + F1 to change to CUI."

echo "continue? [y/N]: "
read val

case "$val" in
  Y|y)
    echo "running..."
    ;;
  * )
    echo "abort"
    exit 0
    ;;
esac

#--rm gnome enviroment--
echo "remove gnome environment"
sudo apt-get remove -y ubuntu-desktop
sudo apt-get -y autoremove
sudo apt-get -y remove nautilus nautilus-* gnome-power-manager gnome-screensaver gnome-termina* gnome-pane* gnome-applet* gnome-bluetooth gnome-desktop* gnome-sessio* gnome-user* gnome-shell-common zeitgeist-core libzeitgeist* gnome-control-center gnome-screenshot && sudo apt-get autoremove

NoUninstall

#--see updates--
echo "--serch and install updates--"
do-release-upgrade
sudo apt update -y
sudo apt upgrade -y

#--install essential apps--
sudo apt install -y zsh build-essential vim python3 python3-pip python3-dev curl wget git vim tlp powertop
yes | sudo apt purge needrestart
#--enable this if you want to run it in VMM--
# sudo apt install spice-vdagent

<< NoStartPowertop
#enable powertop and tlp
sudo powertop --calibrate
sudo systemctl enable --now tlp.service
NoStartPowertop

#--install window manager, etc.--
sudo apt install -y sway swaybg swayidle swaylock xdg-desktop-portal-wlr xwayland
sudo apt install -y wdisplays kanshi waybar sway-notification-center grimshot wofi
sudo apt install -y gammastep

#fcitx mozc
sudo apt install -y fcitx5 fcitx5-mozc

# WebRTC
sudo apt install -y pipewire-audio wireplumber pipewire-media-session-
systemctl --user --now enable wireplumber.service
systemctl --user --now enable pipewire-pulse

sudo apt install -y pavucontrol playerctl
#bluetooth
sudo apt install -y bluetooth blueman

#fontmanager
sudo apt install -y fonts-vlgothic fonts-ipafont
sudo apt install -y fonts-noto-cjk
sudo apt install -y fonts-noto-color-emoji

sudo apt install -y brightnessctl network-manager-gnome

#clipboard
sudo apt install -y wl-clipboard clipman

#Neovim
sudo snap install -y nvim --classic

#Google Chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/google-chrome.deb
sudo apt update -y
sudo apt install -y /tmp/google-chrome.deb

#Brave Browser
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main"|sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update -y
sudo apt install -y brave-browser


#--install vscode--
sudo apt install -y curl apt-transport-https
sudo curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
sudo apt update
sudo apt install -y code

#--install rust--
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

sudo apt install -y meson libwayland-dev libgtk-3-dev gobject-introspection libgirepository1.0-dev gtk-doc-tools valac

# build and install wleave
(
  cd /tmp
  git clone https://github.com/wmww/gtk-layer-shell.git
  cd gtk-layer-shell
  meson setup -Dexamples=true -Ddocs=true -Dtests=true build
  ninja -C build
  sudo ninja -C build install
  sudo ldconfig
  cd /tmp
  git clone https://github.com/AMNatty/wleave.git
  cd wleave
  mkdir /bin/wleave
  make
  cp /tmp/wleave/target/release/wleave /bin/wleave/
)
cp ./lib/wleave.sh /etc/profile.d/

<< Nocopy
for dotfile in .??*; do
    [ "$dotfile" = ".git" ] && continue
    rm -r "$HOME/$dotfile"
    cp -rf "$(pwd)/$dotfile" "$HOME/$dotfile"
done

cd config
for conf in ??*; do
    rm -r "$HOME/.config/$conf"
    cp -rf "$(pwd)/$conf" "$HOME/.config/$conf"
done
cd ..

chsh -s /usr/bin/zsh
zsh

echo "---Installation completed---"