# aus modules/programs/shell.nix (Arch-Pfade)
# WICHTIG: Alles Interaktive nur bei interaktiver Shell. start-umbriel startet
# die Session ueber die Login-Shell (fish -l -c ...) - ohne diese Pruefung
# wuerde fastfetch auf dem VT aufblitzen (wie programs.fish.interactiveShellInit
# auf NixOS, das nur interaktiv laeuft).
set -g fish_greeting ""

if status is-interactive
    zoxide init fish | source

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
end
