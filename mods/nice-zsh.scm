(add-packages! "vim" "zsh" "starship" "eza" "bat")
(let* ((config_home (get-host-env "XDG_CONFIG_HOME" #f))
       (dotfiles (get-host-env "DOTFILES" #f))
       (zcode (mk-path dotfiles "zsh" "code"))
       (c-home (mk-path "/home" container-user)))
  (begin
    (set! shellrc-contents
     "
HISTFILE=$HOME/.histfile
HISTSIZE=1000
SAVEHIST=100000

setopt extended_history
setopt inc_append_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_ignore_all_dups
setopt hist_find_no_dups
setopt hist_save_no_dups
setopt hist_reduce_blanks
setopt no_share_history
setopt no_beep
bindkey -e
zstyle :compinstall filename $ZDOTDIR/.zshrc
autoload -Uz compinit
compinit -Cd .zcompdump

unalias run-help &> /dev/null # Unalias run-help=man
autoload run-help
autoload -Uz colors && colors

# precmd hook to allow jumping to prev commands with <C-Z|X> (foot feature)
function precmd() {
   print -n \"\\e]133;A\\e\\\\\"
}
function set_win_title(){
   print -Pn \"\\033]2; foot: %~ \\007\"
}
precmd_functions+=(set_win_title)
eval \"$(starship init zsh)\"
function overwrite_starship_zle-keymap-select() {
   zle reset-prompt
   zle -R \"\"
}
zle -N zle-keymap-select overwrite_starship_zle-keymap-select

export GPG_TTY=$(tty)

alias cls='clear'
alias please='sudo'
alias pls='sudo'

alias ls='eza -la'
alias cat='/usr/bin/env bat'
         ")
    (add-link! (mk-path c-home ".config" "starship.toml")
               (host-export! (mk-path config_home "starship.toml")))))
