#!/bin/bash
set -e

sudo apt update
sudo apt install -y fzf zoxide ripgrep fd-find zstd hx npm

# npm is for mcp servers in opencode

rm -rf ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# add zsh-autosuggestions to plugins if not already present
if ! grep -q "zsh-autosuggestions" ~/.zshrc; then
  sed -i '/^plugins=(/ s/)/ zsh-autosuggestions)/' ~/.zshrc
fi

# add fzf to .zshrc if not already present
if ! grep -q 'eval "$(fzf --zsh)"' ~/.zshrc; then
cat >> ~/.zshrc << 'EOF'

eval "$(fzf --zsh)"

eval "$(zoxide init zsh)"

# that autosuggestions are gray, instead of white & helix has colors
export TERM=xterm-256color
export COLORTERM=truecolor

EOF
fi


echo ""
echo ""
echo "   now run: source ~/.zshrc"
echo ""
echo ""
