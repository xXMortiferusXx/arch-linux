# aus modules/programs/shell.nix (Arch-Pfade)
set -g fish_greeting ""
zoxide init fish | source

# fastfetch beim Start (wie in modules/programs/fastfetch.nix)
if test -f /etc/fastfetch/config.jsonc
    fastfetch --config /etc/fastfetch/config.jsonc
end

if test "$TERM" = linux
    # Textkonsole: kein Nerd-Font -> keine Icons, schlichter Prompt
    alias ls "eza --group-directories-first"
    alias l "eza -l --group-directories-first"
    alias la "eza -la --group-directories-first"
    alias ll "eza -lha --group-directories-first"
    alias tree "eza --tree"
    function fish_prompt
        printf '%s > ' (prompt_pwd)
    end
else
    starship init fish | source
    alias ls "eza --icons --group-directories-first"
    alias l "eza -l --icons --group-directories-first"
    alias la "eza -la --icons --group-directories-first"
    alias ll "eza -lha --icons --group-directories-first"
    alias tree "eza --tree --icons"
end

alias .. "cd .."
alias ... "cd ../.."
alias .... "cd ../../.."
alias grep "grep --color=auto"
alias cat "bat"
alias fetch "fastfetch"

abbr -a gs "git status"
abbr -a ga "git add"
abbr -a gc "git commit"
