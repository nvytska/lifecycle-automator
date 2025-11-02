#!/bin/bash
set -euo pipefail

create_repo(){
    local repo_path="$1"
     
    mkdir -p "$repo_path"
    cd "$repo_path"

    read -rp "Enter project name: " PNAME
    read -rp "Enter main branch name: " BRANCH
    BRANCH=${BRANCH:-main}
    git init --initial-branch="$BRANCH"
    git commit --allow-empty -m "Initial empty snapshot for $PNAME"

    while true; do
        read -rp "Add a submodule? (Y/N): " add_sub
        if [[ "$add_sub" =~ ^[Yy]$ ]]; then
            read -rp "Enter submodule local path: " sub_path
            read -rp "Enter submodule source directory: " sub_srcdir
            read -rp "Enter target revision or branch: " sub_rev

            git config --local protocol.file.allow always

            git submodule add "$sub_srcdir" "$sub_path" || {
            echo "Failed to add submodule. Please check paths."
            continue
            }

            (
                cd "$sub_path" || exit 1
                git checkout "$sub_rev"  || {
                    echo "Warning: revision/branch '$sub_rev' not found, staying on default branch."
                }
            )
        elif [[ "$add_sub" =~ ^[Nn]$ ]]; then
            break
        else 
            echo "Invalid option."
            continue
        fi
    done

    echo "Let's create a commit message template:"
    local sections=()
    for i in {1..3}; do
        read -rp "Enter name for section $i: " section
        [[ -z "$section" ]] && break
        sections+=("$section")
    done
    [[ ${#sections[@]} -eq 0 ]] && sections=("Section1" "Section2" "Section3")

    local template_file=".git/hooks/commit-msg-template.txt"
    {
        echo "${PNAME}-123: some text"
        echo
        for s in "${sections[@]}"; do
            echo "${s}:"
            echo "..."
        done
    } > "$template_file"
    echo "Preview of commit message template:"
    cat "$template_file"
    while true; do
        read -rp "Approve this template? (Y/N): " approve
        if [[ "${approve}" =~ ^[Nn]$ ]]; then
            echo "Template not approved. Restart 'create' command to redefine sections."
            return 1
        elif [[ "${approve}" =~ ^[Yy]$ ]]; then
            echo "Congratiluations! Template approved."
            break
        else 
            echo "Invalid option. Enter Y on N." 
        fi
    done

    local hook_file=".git/hooks/commit-msg"
    cat > "$hook_file" <<'EOF'
#!/bin/bash

TEMPLATE_FILE=".git/hooks/commit-msg-template.txt"
COMMIT_MSG_FILE="$1"

if [[ -f ".git/MERGE_HEAD" ]]; then
    exit 0
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "Template file not found at $TEMPLATE_FILE" 
    exit 1
fi

PNAME=$(head -1 "$TEMPLATE_FILE" | cut -d'-' -f1)
MESSAGE=$(head -1 "$COMMIT_MSG_FILE")

if ! grep -Eq "^${PNAME}-[0-9]+:" <<< "$MESSAGE"; then
    echo "Commit message must start with '${PNAME}-<ticket>: <summary>'"
    exit 1
fi

SECTIONS=$(tail -n +2 "$TEMPLATE_FILE" | grep -E '^[A-Za-z0-9_-]+:' | sed 's/://')
for section in $SECTIONS; do
    if ! grep -qE "^${section}:" "$COMMIT_MSG_FILE"; then
        echo "Missing required section: ${section}" 
        exit 1
    fi
    if ! awk -v sec="$section" '
        BEGIN {found=0; ok=0}
        $0 ~ "^" sec ":" {found=1; next}
        found && /^[A-Za-z0-9_-]+:/ {exit}
        found && NF>0 {ok=1}
        END {exit ok ? 0 : 1}
    ' "$COMMIT_MSG_FILE"; then
        echo "Section ${section} has no content."
        exit 1
    fi
done

exit 0
EOF

    chmod +x "$hook_file"
    echo "commit-msg hook installed."
    echo

    echo "Repository summary:"
    printf "%-20s %-40s\n" "Path:" "$repo_path"
    printf "%-20s %-40s\n" "Branch:" "$BRANCH"
    printf "%-20s %-40s\n" "Template file:" "$template_file"
    printf "%-20s %-40s\n" "Hook file:" "$hook_file"
    echo "Repository creation complete!"
}

validate_commits(){
    local repo_path="$1"
    local ref="${2:-HEAD}"

    cd "$repo_path"
    local template_file=".git/hooks/commit-msg-template.txt"
    local pname
    local sections=()

    if [[ -f "$template_file" ]]; then
        pname=$(head -1 "$template_file" | cut -d'-' -f1)
        sections=()
        while IFS= read -r line; do
            sections+=("$line")
        done < <(grep -E '^[A-Za-z0-9_-]+:' "$template_file" | sed 's/://')
    else
        read -rp "Template not found. Enter project name (PNAME): " pname
        read -rp "Enter required sections (comma separated): " section_input
        IFS=',' read -ra sections <<< "$section_input"
    fi
    local commits
    commits=$(git log "$ref" --no-merges --pretty=format:"%h|%an|%ad|%cn|%cd|%s")

    if [[ -z "$commits" ]]; then
        echo "No commits found for $ref."
        return 0
    fi

    local has_violations=false
    printf "%-10s | %-15s | %-15s | %-40s\n" "SHA" "Author" "Date" "Violation"
    echo "------------------------------------------------------------------------------------------"

    while IFS='|' read -r sha author ad committer cd msg; do
        local violation=""

        if ! grep -qE "^${pname}-[0-9]+:" <<< "$msg"; then
            violation+="Invalid prefix (expected ${pname}-<ticket>: ...); "
        fi

        local full_msg
        full_msg=$(git log -1 --format=%B "$sha")

        for s in "${sections[@]}"; do
            if ! grep -qE "^${s}:" <<< "$full_msg"; then
                violation+="Missing section ${s}; "
            fi
        done

        if [[ -n "$violation" ]]; then
            has_violations=true
            printf "%-10s | %-15s | %-15s | %-40s\n" "$sha" "$author" "$(date -d "$ad" +'%Y-%m-%d')" "$violation"
        fi
    done <<< "$commits"

    if [[ "$has_violations" == false ]]; then
        echo "All commits conform to template."
    else
        echo "Some commits do not conform to template."
    fi


}

check_submodules(){
    local repo_path="$1"

    cd "$repo_path"
    if [[ ! -f ".gitmodules" ]]; then
        echo "No submodules found."
        return 0
    fi

    count=$(find . -type f -name ".gitmodules" | wc -l)

    if [ "$count" -gt 1 ]; then
        echo "Nested submodules detected:"
        find . -type f -name ".gitmodules" -print
    fi

    submodules=()
    while IFS= read -r sm; do
        submodules+=("$sm")
    done < <(grep -E 'path *= *' .gitmodules | awk -F'= ' '{print $2}')
    if [[ ${#submodules[@]} -eq 0 ]]; then
        echo "No submodules declared in .gitmodules."
        return 0
    fi
    local changes_staged=false
    local summary_file
    summary_file=$(mktemp)

    for sm in "${submodules[@]}"; do
        echo
        echo "Processing submodule: $sm"

        if [[ ! -d "$sm/.git" ]]; then
            echo "Invalid submodule path: $sm"
            continue
        fi

        (
            cd "$sm" || exit 1
            local status
            status=$(git status --porcelain)

            if [[ -z "$status" ]]; then
                echo "No changes in $sm (gitlink SHA: $(git rev-parse --short HEAD))"
                echo "| $sm | 0/0 | No | $(git rev-parse --short HEAD) |" >> "$summary_file"
                exit 0
            fi

            echo "Changes detected in $sm:"
            git --no-pager diff --stat

            read -rp "Create commit for changes in $sm? (Y/N): " ans
            if [[ ${ans} =~ ^[Yy]$ ]]; then
                git add .
                git commit
                new_sha=$(git rev-parse --short HEAD)
                echo "Committed changes in $sm (new SHA: $new_sha)"
                echo "| $sm | $(git diff --shortstat HEAD~1 HEAD | sed 's/files* changed,//') | Yes | $new_sha |" >> "$summary_file"
                exit 2 
            else
                echo "Skipped committing changes in $sm."
                echo "| $sm | pending | No | $(git rev-parse --short HEAD) |" >> "$summary_file"
                exit 0
            fi
        )
        local code=$?
        if [[ $code -eq 2 ]]; then
            git add "$sm"
            changes_staged=true
        fi
    done

    if $changes_staged; then
        read -rp "Commit submodule updates to parent repo? (Y/N): " parent_commit
        if [[ "${parent_commit}" =~ ^[Yy]$ ]]; then
            git commit
            echo "Parent repository updated with submodule commits."
        else
            echo "Skipped committing parent update."
        fi
    else
        echo "No submodule changes staged in parent."
    fi

    echo "Submodule Summary:"
    echo "| Submodule | Added/Removed | Committed | New SHA |"
    cat "$summary_file"
    rm -f "$summary_file"
}


interactive_menu(){
    local choice
    local repo_path
    clear
    echo "Git Repository Lifecycle Automator"
    
    while true; do
        echo "Select an option:"
        echo "create            Create Repository"
        echo "validate          Validate Commits"
        echo "submodule_check   Check and Commit Submodules"
        echo "exit              Exit the script"
        read -rp "Enter choice: " choice

        case "$choice" in
            create)
                echo
                read -rp "Enter path for new repository: " repo_path
                create_repo "$repo_path"
                echo
                ;;
            validate)
                echo
                read -rp "Enter path for new repository: " repo_path
                validate_commits "$repo_path"
                echo
                ;;
            submodule_check)
                echo
                read -rp "Enter path for new repository: " repo_path
                check_submodules "$repo_path"
                echo
                ;;
            exit)
                echo "Exiting"
                break
                ;;
            *)
                echo "Invalid option"
                echo "Available commands: create, validate, submodule_check, exit"
                exit 1
                ;;
        esac
    done
}


main(){
    if [[ $# -lt 2 ]]; then
        interactive_menu
    fi
    if [[ $# -gt 2 ]]; then
        echo "Invalid number of arguments."
        echo "Usage: $(basename "$0") [repo_path] [command]"
        exit 1
    fi

    local repo_path="$1"
    local command="$2"

    case "$command" in
        create)
            create_repo "$repo_path"
            ;;
        validate)
            validate_commits "$repo_path"
            ;;
        submodule_check)
            check_submodules "$repo_path"
            ;;
        *)
            echo "Unknown command: $command"
            echo "Available commands: create, validate, submodule_check"
            exit 1
            ;;
    esac

}

main "$@"