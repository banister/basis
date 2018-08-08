#!/bin/bash

# curl https://raw.githubusercontent.com/banister/basis/master/basis.sh > ~/foo.sh

set -e # abort script on first error

RUBY_VERSION=2.5.0

RED="$(tput setaf 1)"
BLUE="$(tput setaf 4)"
BOLD="$(tput bold)"
NORMAL="$(tput sgr0)"

# The list of things successfully installed
# List is appended to as installation happpens.
COMPLETED_INSTALLS=""

echo_error() {
    echo "${RED}${BOLD}ERROR: ${NORMAL}$@" >&2
    echo "${NORMAL}"
}

echo_info() {
    echo "${BLUE}${BOLD}INFO: ${NORMAL}$@"
}

if [ -z $DROPBOX_TOKEN ]; then
    echo_error "You need to export the DROPBOX_TOKEN environment variable!"
    exit 1
fi

setup_git() {
    download_file /configfiles/git/dot-gitconfig ~/.gitconfig
    prepare_command git
}

wrap_with_messages() {
    echo_info "Setting up $1"
    setup_$1
    echo_info "Finished setting up ${1}!"
    COMPLETED_INSTALLS="$COMPLETED_INSTALLS $1"
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
        echo_info "nano already configured"
        return
    fi

    git clone https://github.com/nanorc/nanorc.git $nano_dir --depth 1
    (cd $nano_dir; make install)

    backup_file ~/.nanorc
    echo "include ~/.nano/syntax/ALL.nanorc" > ~/.nanorc
}

setup_ruby() {
    if [ -e ~/.rbenv ]; then
        echo_info "ruby already installed"
        return
    fi

    local updated_path="PATH=~/.rbenv/bin:$PATH"
    case $(uname -s) in
        Darwin)
            wrap_with_messages homebrew
            brew install openssl libyaml libffi
            brew install rbenv
            ;;
        Linux)
            git clone https://github.com/rbenv/rbenv.git ~/.rbenv --depth 1
            mkdir -p ~/.rbenv/plugins
            git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build --depth 1
            sudo apt update
            sudo apt install -y gcc autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm3 libgdbm-dev
            ;;
        *)
            echo_error "UNSUPPORTED OS VERSION $(uname -s)"
            ;;
    esac

    eval $updated_path
    eval "$(rbenv init -)"
    rbenv install $RUBY_VERSION
    rbenv global $RUBY_VERSION
    gem install pry pry-doc --no-document
}

setup_osx_apps() {
    brew install cask
    brew install ripgrep jq cscope zsh
}

setup_linux_apps() {
    sudo apt install -y cscope jq zsh
}

download_file() {
    # if the destination file already exists, back it up
    backup_file "$2"
    prepare_command curl

    curl -ksL -X POST https://content.dropboxapi.com/2/files/download \
         --header "Authorization: Bearer ${DROPBOX_TOKEN}" \
         --header "Dropbox-API-Arg: {\"path\": \"${1}\"}" -o "$2"

    if [ $? -ne 0 ]; then
        echo_error "Failed to make a request to dropbox, file path was: $1"
        exit 1
    fi
}

prepare_command() {
    if which "$1" > /dev/null 2>&1; then
        return
    fi

    case $(uname -s) in
        Darwin)
            if ! which brew > /dev/null 2>&1; then
                setup_homebrew
            fi

            brew install "$1"
            ;;
        Linux)
            sudo apt install -y "$1"
            ;;
        *)
            echo_error "Failed to install $1"
    esac
}

backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1".bak
    fi
}

setup_homebrew() {
    if which brew > /dev/null 2>&1; then
        echo_info "homebrew already installed."
        return
    fi

    /usr/bin/ruby -e "$(curl -kfsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
}

setup_apps() {
    if which jq > /dev/null 2>&1; then
        echo_info "apps already installed"
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
            echo_error "UNSUPPORTED OS VERSION $(uname -s)"
            ;;
    esac
}

setup_zsh() {
    if [ -e ~/.oh-my-zsh ]; then
        echo_info "oh-my-zsh already installed"
        return
    fi

    # doctored oh-my-zsh installer that doesn't invoke zsh after installation
    sh -c "$(curl -kfsSL https://raw.githubusercontent.com/banister/basis/master/setup_ohmyzsh.sh)"
    write_to_zshrc 'ZSH_THEME="robbyrussell"'
    write_to_zshrc 'PATH=~/.rbenv/bin/:$PATH'
    write_to_zshrc 'eval "$(rbenv init -)"'
    write_to_zshrc 'export CSCOPE_EDITOR=nano'
    write_to_zshrc 'CODE=~/code'
    write_to_zshrc 'PRY=~/code/pry'
    write_to_zshrc 'PIA=~/code/pia/pia_manager'
    write_to_zshrc 'export CSCOPE_EDITOR=nano'
    write_to_zshrc 'export LESS="-R -X -F $LESS"'
    write_to_zshrc 'alias be="bundle exec"'

    if ! grep 'function cr' ~/.zshrc; then
        cat << 'EOF' >> ~/.zshrc
function cr {
  coderay $@ | less -N
}

EOF
    fi

    if ! grep 'function cscope_setup' ~/.zshrc; then
        cat << 'EOF' >> ~/.zshrc
function cscope_setup {
  echo "setting up cscope for the PWD"
  set -x
  find . -name "*.c" -o -name "*.h" > cscope.files

  # pass on args so we can invoke with, say, cscope_setup -k, to leave out
  # system headers if building kernel for example
  cscope -q -b $@
  echo "all setup! type cscope -d"
}
EOF
    fi

    if ! grep 'function cdc' ~/.zshrc; then
        cat << 'EOF' >> ~/.zshrc
function cdc {
    if [ $# -le 0 ]; then
        cd ~/code
        return
    fi

    local result=$(find ~/code -maxdepth 4 -type d -name "*$@*" | \
      awk '{ print length, $0 }' | sort -n | head -1 | cut -f2- -d' ')

    if [ -z $result ]; then
        echo "No match found for '$@'" >&2
    else
        cd "$result"
    fi
}
EOF
    fi
}

setup_direcs() {
    mkdir -p ~/code
}

write_to_zshrc() {
    if grep -q "$@" ~/.zshrc; then
        return
    fi

    echo "$@" >> ~/.zshrc
}

completion_message() {
    echo
    for i in $COMPLETED_INSTALLS; do
        echo_info "$i is setup"
    done

    echo
    echo "${BOLD}###############################"
    echo "${BOLD}# Finished setting up system! #"
    echo "${BOLD}###############################"
    echo "${NORMAL}"
}

main() {
    wrap_with_messages git
    wrap_with_messages ssh
    wrap_with_messages ruby
    wrap_with_messages nano
    wrap_with_messages apps
    wrap_with_messages direcs

    # must be last as oh-my-zsh installation enters the zsh
    wrap_with_messages zsh

    # done!
    completion_message

    # now change to zsh
    echo_info "Now changing shell to zsh! Goodbye!"
    env zsh
}

# start
main
