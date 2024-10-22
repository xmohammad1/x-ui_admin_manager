#!/bin/bash

# Define the database path
DB_PATH="/etc/x-ui/x-ui.db"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to print error messages
print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}Success: $1${NC}"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Function to validate database connection
validate_db() {
    if ! sqlite3 "$DB_PATH" "SELECT 1;" >/dev/null 2>&1; then
        print_error "Cannot connect to database"
        return 1
    fi
    return 0
}

# Function to check if the database file exists and is readable
check_db() {
    if [ ! -f "$DB_PATH" ]; then
        print_error "Database file not found: $DB_PATH"
        exit 1
    fi
    if [ ! -r "$DB_PATH" ]; then
        print_error "Cannot read database file: $DB_PATH"
        exit 1
    fi
    validate_db || exit 1
}

# Function to validate username
validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; then
        print_error "Username must be 3-32 characters long and contain only letters, numbers, underscores, and hyphens"
        return 1
    fi
    return 0
}

# Function to check if user exists
user_exists() {
    local username="$1"
    local count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE username='$username';")
    return $((count > 0))
}

# Function to display all users
show_users() {
    check_db
    echo -e "\n            ${BLUE}=== X-UI User Admin Management System ===${NC}\n"

    # Get the count of users
    user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")
    
    if [ "$user_count" -eq 0 ]; then
        echo -e "${BLUE}|------------------------------------------------------------------|${NC}"
        echo -e "${BLUE}|${NC}${RED}                    No users found in database.                   ${NC}${BLUE}|${NC}"
        echo -e "${BLUE}|------------------------------------------------------------------|${NC}"
    else
        # Print table header
        echo -e "${BLUE}|----------------------------------------------------------------|${NC}"
        echo -e "${BLUE}|${NC} ${MAGENTA}ID${BLUE} |${NC} Username           ${BLUE}|${NC} Password                  ${BLUE}|${NC} Is Sudo  ${BLUE}|${NC}"
        echo -e "${BLUE}|----------------------------------------------------------------|${NC}"
        
        # Fetch and display user data with proper color handling
        while IFS='|' read -r id username password is_sudo; do
            # Print each row with formatting and direct color codes
            if [ "$is_sudo" -eq 1 ]; then
                printf "${BLUE}|${NC} ${MAGENTA}%-3s${BLUE}|${NC} %-18s ${BLUE}|${NC} %-25s ${BLUE}|${NC} ${GREEN}%-8s${NC} ${BLUE}|${NC}\n" \
                       "$id" "$username" "$password" "Yes"
            else
                printf "${BLUE}|${NC} ${MAGENTA}%-3s${BLUE}|${NC} %-18s ${BLUE}|${NC} %-25s ${BLUE}|${NC} ${RED}%-8s${NC} ${BLUE}|${NC}\n" \
                       "$id" "$username" "$password" "No"
            fi
            echo -e "${BLUE}|----------------------------------------------------------------|${NC}"
        done < <(sqlite3 "$DB_PATH" "SELECT id, username, password, is_sudo FROM users;")
        
        # Print total users
        echo -e "${BLUE}Total users: ${MAGENTA}$user_count${NC}"
    fi
}
# Function to add a new user
add_user() {
    check_db
    
    while true; do
        read -p "Enter username: " username
        if validate_username "$username"; then
            if ! user_exists "$username"; then
                print_error "Username already exists"
                continue
            fi
            break
        fi
    done

    read -p "Enter password: " password

    while true; do
        read -p "Is the user sudo? (1 for yes, 0 for no): " is_sudo
        if [[ "$is_sudo" =~ ^[0-1]$ ]]; then
            break
        fi
        print_error "Please enter 0 or 1"
    done

    if sqlite3 "$DB_PATH" "INSERT INTO users (username, password, login_secret, is_sudo) VALUES ('$username', '$password', '', $is_sudo);" 2>/dev/null; then
        print_success "User '$username' added successfully"
    else
        print_error "Failed to add user to database"
        return 1
    fi
}

# Function to remove a user
remove_user() {
    check_db
    
    read -p "Enter the username to remove: " username
    if ! validate_username "$username"; then
        return 1
    fi

    if user_exists "$username"; then
        print_error "User '$username' does not exist"
        return 1
    fi

    read -p "Are you sure you want to remove user '$username'? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "User removal cancelled"
        return 0
    fi

    if sqlite3 "$DB_PATH" "DELETE FROM users WHERE username='$username';" 2>/dev/null; then
        print_success "User '$username' removed successfully"
    else
        print_error "Failed to remove user from database"
        return 1
    fi
}

# Function to modify a user
modify_user() {
    check_db
    
    read -p "Enter the username to modify: " username
    if ! validate_username "$username"; then
        return 1
    fi

    if user_exists "$username"; then
        print_error "User '$username' does not exist"
        return 1
    fi
    # New username modification option
    read -p "Enter new username (leave blank to keep current): " new_username
    if [ -n "$new_username" ]; then
        if ! validate_username "$new_username"; then
            return 1
        fi
        # Check if the new username already exists (but ignore if it's the same as current)
        if [ "$username" != "$new_username" ]; then
            if ! user_exists "$new_username"; then
                print_error "Username '$new_username' already exists"
                return 1
            fi
        fi
        if ! sqlite3 "$DB_PATH" "UPDATE users SET username='$new_username' WHERE username='$username';" 2>/dev/null; then
            print_error "Failed to update username"
            return 1
        fi
        print_success "Username changed from '$username' to '$new_username'"
        username="$new_username"  # Update username for subsequent operations
        changes_made=1
    fi
    local changes_made=0
    read -p "Enter new password (leave blank to keep current): " password
    if [ -n "$password" ]; then
        if ! sqlite3 "$DB_PATH" "UPDATE users SET password='$password' WHERE username='$username';" 2>/dev/null; then
            print_error "Failed to update password"
            return 1
        fi
        print_success "Password updated successfully"
        changes_made=1
    fi

    read -p "Is the user sudo? (1 for yes, 0 for no, leave blank to keep current): " is_sudo
    if [ -n "$is_sudo" ]; then
        if [[ ! "$is_sudo" =~ ^[0-1]$ ]]; then
            print_error "Invalid sudo value. Please enter 0 or 1"
            return 1
        fi
        if ! sqlite3 "$DB_PATH" "UPDATE users SET is_sudo=$is_sudo WHERE username='$username';" 2>/dev/null; then
            print_error "Failed to update sudo status"
            return 1
        fi
        print_success "Sudo status updated successfully"
        changes_made=1
    fi

    if [ $changes_made -eq 1 ]; then
        print_success "User modifications completed successfully"
    else
        print_warning "No changes were made to user '$username'"
    fi
}

# Trap Ctrl+C and other signals
trap 'echo -e "\n${YELLOW}Script interrupted${NC}"; exit 1' SIGINT SIGTERM

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi
press_enter() {
    echo -ne "${GREEN}Press Enter to continue...${NC}"
    read
}
# Menu for user options
while true; do
    show_users
    echo -e "\n${GREEN}User Admin Management Menu${NC}"
    echo "1) Add a user"
    echo "2) Remove a user"
    echo "3) Modify a user"
    echo "4) Exit"
    read -p "Enter choice [1-4]: " choice
    echo

    case $choice in
        1) add_user ;;
        2) remove_user ;;
        3) modify_user ;;
        0) print_success "Exiting..."; exit 0 ;;
        *) print_error "Invalid option. Please try again." ;;
    esac
done
