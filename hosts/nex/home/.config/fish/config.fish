# aus modules/programs/shell.nix (Arch-Pfade)
set -g fish_greeting ""
zoxide init fish | source
starship init fish | source

alias ls "eza --icons --group-directories-first"
alias ll "eza -lha --icons --group-directories-first"
alias tree "eza --tree --icons"
alias .. "cd .."
alias ... "cd ../.."
alias .... "cd ../../.."
alias grep "grep --color=auto"
alias cat "bat"
alias fetch "fastfetch"

abbr -a gs "git status"
abbr -a ga "git add"
abbr -a gc "git commit"
