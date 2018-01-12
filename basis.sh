#!/bin/bash

# https://raw.githubusercontent.com/banister/basis/master/basis.sh

RUBY_VERSION=2.5.0

set -e

if [ -z DROPBOX_TOKEN ]; then
    echo "ERROR: You need to set the DROPBOX_TOKEN environment variable!"
    exit 1
fi

setup_git() {
    download_file /configfiles/git/dot-gitconfig ~/.gitconfig
}

wrap_with_messages() {
    echo "Setting up $1"
    setup_$1
    echo "OK: finished setting up ${1}!"
}

setup_ssh() {
    mkdir -p ~/.ssh
    download_file /configfiles/ssh-files/id_rsa.pub ~/.ssh/id_rsa.pub
    download_file /configfiles/ssh-files/id_rsa ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
}

setup_nano() {
    local nano_dir=~/nanorc
    if [ -e "$nano_dir" ]; then
        echo "INFO: nano already configured"
        return
    fi

    git clone https://github.com/nanorc/nanorc.git $nano_dir --depth 1
    (cd $nano_dir; make install)

    backup_file ~/.nanorc
    echo "include ~/.nano/syntax/ALL.nanorc" > ~/.nanorc
}

setup_ruby() {
    if [ -e ~/.rbenv ]; then
        echo "INFO: ruby already installed"
        return
    fi

    local updated_path="PATH=~/.rbenv/bin:$PATH"
    case $(uname -s) in
        Darwin)
            wrap_with_messages homebrew
            brew install openssl libyaml libffi
            brew install rbenv
            rbenv install $RUBY_VERSION
            ;;
        Linux)
            git clone https://github.com/rbenv/rbenv.git ~/.rbenv --depth 1
            mkdir -p ~/.rbenv/plugins
            git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build --depth 1
            sudo apt update
            sudo apt install gcc-6 autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm3 libgdbm-dev
            rbenv install $RUBY_VERSION
            ;;
        *)
            echo "ERROR: UNSUPPORTED OS VERSION $(uname -s)"
            ;;
    esac

    eval $updated_path
    eval "$(rbenv init -)"
    rbenv global $RUBY_VERSION
    gem install pry pry-doc --no-document
}

setup_osx_apps() {
    brew install cask
    brew tap d12frosted/emacs-plus
    brew install emacs-plus ripgrep jq cscope zsh
    brew linkapps emacs-plus
}

setup_linux_apps() {
    sudo apt install emacs24 cscope ack-grep jq zsh
}

download_file() {
    # if the destination file already exists, back it up
    backup_file "$2"

    curl -sL -X POST https://content.dropboxapi.com/2/files/download \
         --header "Authorization: Bearer ${DROPBOX_TOKEN}" \
         --header "Dropbox-API-Arg: {\"path\": \"${1}\"}" -o "$2"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to make a request to dropbox, file path was: $1"
        exit 1
    fi
}

backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1".bak
    fi
}

setup_homebrew() {
    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
}

setup_spacemacs() {
    if [ -e ~/.emacs.d/spacemacs.mk ]; then
        echo "INFO: spacemacs already installed"
        return
    fi

    git clone https://github.com/syl20bnr/spacemacs ~/.emacs.d --depth 1
    download_file /configfiles/emacs/dot-spacemacs ~/.spacemacs
}

setup_apps() {
    if which jq > /dev/null 2>&1; then
        echo "INFO: apps already installed"
        return
    fi

    case $(uname -s) in
        Darwin)
            wrap_with_messages osx_apps
            ;;
        Linux)
            wrap_with_messages linux_apps
            ;;
        *)
            echo "ERROR: UNSUPPORTED OS VERSION $(uname -s)"
            ;;
    esac
}

setup_zsh() {
    if [ -e ~/.oh-my-zsh ]; then
        echo "INFO: oh-my-zsh already installed"
        return
    fi

    sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
    echo 'ZSH_THEME="robbyrussell"' >> ~/.zshrc
    echo 'PATH=~/.rbenv/bin/:$PATH' >> ~/.zshrc
    echo 'eval "$(rbenv init -)"' >> ~/.zshrc
    echo 'export CSCOPE_EDITOR=nano' >> ~/.zshrc
    echo 'CODE=~/code' >> ~/.zshrc
    echo 'PRY=~/code/pry' >> ~/.zshrc
    echo 'PIA=~/code/pia/pia_manager' >> ~/.zshrc
    echo 'export CSCOPE_EDITOR=nano' >> ~/.zshrc
    echo 'export LESS="-R -X -F $LESS"' >> ~/.zshrc
    echo 'alias be="bundle exec"' >> ~/.zshrc

    cat << 'EOF' >> ~/.zshrc
function cr {
  coderay $1 | less -N
}
EOF

    cat << 'EOF' >> ~/.zshrc
function cscope_setup {
  echo "setting up cscope for the PWD"
  set -x
  find . -name "*.c" -o -name "*.h" > cscope.files
  cscope -q -b
  echo "all setup! type cscope -d"
}
EOF
}

create_or_append() {
    if [ -f "$2" ]; then
        echo "$1" >> "$2"
    else
        echo "$1" > "$2"
    fi
}

main() {
    wrap_with_messages git
    wrap_with_messages ssh
    wrap_with_messages ruby
    wrap_with_messages nano
    wrap_with_messages spacemacs
    wrap_with_messages apps
    wrap_with_messages zsh
}

# start
main
