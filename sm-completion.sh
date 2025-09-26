

#!/usr/bin/env bash

_sm_completion() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    # Commands available in sm
    local commands="add start stop logs ls list remove rm workdir dive update install-helpers help"
    
    # Get project names from the registry file
    local sm_dir="$HOME/.sm"
    local projects_file="$sm_dir/projects.txt"
    local projects=""
    
    if [[ -f "$projects_file" ]]; then
        projects=$(cut -d: -f1 "$projects_file" 2>/dev/null)
    fi

    # First argument - complete commands
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    # Second argument - complete based on command
    if [[ $cword -eq 2 ]]; then
        case "$prev" in
            start|stop|logs|remove|rm|workdir|dive)
                # Complete with project names
                COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
                return 0
                ;;
            *)
                # No completion for other commands
                return 0
                ;;
        esac
    fi
}

# Register the completion function for the sm command
complete -F _sm_completion sm
