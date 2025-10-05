# Wrapper function for sm command to handle dive specially
_sm_wrapper() {
    if [[ "$1" == "dive" || "$1" == "cd" ]]; then
        if [[ $# -eq 1 ]]; then
            echo "Where are we diving? Provide a project name please"
            return 1
        fi
        local target_dir
        target_dir=$(command sm workdir "$2" 2>/dev/null)
        if [[ $? -eq 0 && -n "$target_dir" ]]; then
            cd "$target_dir"
            echo "Changed directory to: $PWD"
        else
            echo "Failed to dive into project: $2" >&2
            return 1
        fi
    else
        # For all other commands, just pass through to the original sm script
        command sm "$@"
    fi
}

# Create alias that overrides the sm command
alias sm='_sm_wrapper'
