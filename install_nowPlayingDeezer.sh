#!/bin/bash

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

BOLD='\033[1m'
ITALIC='\033[3m'
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'

show_logo() {
    echo -e "${CYAN}"
    cat << "EOF"
 _   _                 ____  _             _
| \ | | _____      __ |  _ \| | __ _ _   _(_)_ __   __ _
|  \| |/ _ \ \ /\ / / | |_) | |/ _` | | | | | '_ \ / _` |
| |\  | (_) \ V  V /  |  __/| | (_| | |_| | | | | | (_| |
|_| \_|\___/ \_/\_/   |_|   |_|\__,_|\__, |_|_| |_|\__, |
                                     |___/         |___/
 ____
|  _ \  ___  ___ ____  ___ _ __
| | | |/ _ \/ _ \_  / / _ \ '__|
| |_| |  __/  __// /_|  __/ |
|____/ \___|\___/____\___|_|
EOF
    echo -e "${RESET}"
}

clear_and_show_logo() {
    clear
    show_logo
}

center_text() {
    local text="$1"
    local width=$(tput cols)
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s%s%${padding}s\n" "" "$text" ""
}

print_fancy_box() {
    local text="$1"
    local width=$(tput cols)
    local box_width=$((width - 4))
    local padding=$(( (box_width - ${#text}) / 2 ))

    echo -e "${CYAN}"
    printf "+%${box_width}s+\n" | tr ' ' '-'
    printf "|%*s%s%*s|\n" $padding "" "$text" $padding ""
    printf "+%${box_width}s+\n" | tr ' ' '-'
    echo -e "${RESET}"
}

show_progress() {
    local duration=$1
    local width=50
    local bar_char="#"
    local empty_char="-"

    for ((i=0; i<=width; i++)); do
        local percent=$((i*100/width))
        local num_bars=$((i*width/width))
        printf "\r[%-${width}s] %d%%" $(printf "%0.s${bar_char}" $(seq 1 $num_bars)) $percent
        sleep $(bc <<< "scale=3; $duration/$width")
    done
    echo
}

info() {
    echo -e "\n${BLUE}ℹ ${ITALIC}${WHITE}$1${RESET}"
}

success() {
    echo -e "\n${GREEN}✔ ${BOLD}${WHITE}$1${RESET}"
}

error() {
    echo -e "\n${RED}✖ ${BOLD}${WHITE}$1${RESET}"
}

warning() {
    echo -e "\n${YELLOW}⚠ ${ITALIC}${WHITE}$1${RESET}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_playerctl_debian() {
    info "Installing playerctl on a Debian-based system..."
    sudo apt update
    sudo apt install -y playerctl
}

install_playerctl_redhat() {
    info "Installing playerctl on a Red Hat-based system..."
    sudo dnf install -y playerctl
}

install_playerctl_arch() {
    info "Installing playerctl on Arch Linux..."
    sudo pacman -S --noconfirm playerctl
}

choose_player() {
    players=($(playerctl -l))
    if [ ${#players[@]} -eq 0 ]; then
        error "No player detected. Make sure Deezer is running."
        exit 1
    fi

    clear_and_show_logo
    print_fancy_box "Available Players"
    for i in "${!players[@]}"; do
        echo -e " ${MAGENTA}${BOLD}$((i+1)).${RESET} ${CYAN}${players[$i]}${RESET}"
    done
    echo

    while true; do
        read -p "$(echo -e ${YELLOW}"Choose the Deezer player number (1-${#players[@]}) : "${RESET})" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#players[@]}" ]; then
            deezer_player=${players[$((choice-1))]}
            break
        else
            warning "Invalid choice. Please enter a number between 1 and ${#players[@]}."
        fi
    done
}

ask_spotify_tokens() {
    clear_and_show_logo
    print_fancy_box "Spotify API Configuration"

    while true; do
        echo -e "${YELLOW}Enter your Spotify Client ID : ${RESET}"
        read -s spotify_client_id
        echo
        if [ -n "$spotify_client_id" ]; then
            echo -e "${GREEN}Client ID saved (length: ${#spotify_client_id})${RESET}"
            break
        else
            echo -e "${RED}Client ID cannot be empty. Please try again.${RESET}"
        fi
    done

    echo

    while true; do
        echo -e "${YELLOW}Enter your Spotify Client Secret : ${RESET}"
        read -s spotify_client_secret
        echo
        if [ -n "$spotify_client_secret" ]; then
            echo -e "${GREEN}Client Secret saved (length: ${#spotify_client_secret})${RESET}"
            break
        else
            echo -e "${RED}Client Secret cannot be empty. Please try again.${RESET}"
        fi
    done
}

check_port() {
    nc -z localhost $1 >/dev/null 2>&1
    return $?
}

find_available_port() {
    local port=$1
    while check_port $port; do
        port=$((port + 1))
    done
    echo $port
}

install_dependencies() {
    info "Installing npm dependencies..."
    npm install
    if [ $? -ne 0 ]; then
        error "Dependency installation failed."
        exit 1
    fi
    success "Dependencies installed successfully."
}

build_app() {
    info "Building the application..."
    npm run build
    if [ $? -ne 0 ]; then
        error "Application build failed."
        exit 1
    fi
    success "Application built successfully."
}

launch_app() {
    info "Launching the application in the background..."
    nohup npm start > app.log 2>&1 &
    success "Application launched successfully. PID: $!"
}

stop_app() {
    info "Searching for running application..."

    pid=$(ps aux | grep "[n]ode.*npm start" | awk '{print $2}')

    if [ -n "$pid" ]; then
        info "Application found with PID: $pid"
        info "Stopping the application..."
        kill $pid
        sleep 2
        if kill -0 $pid 2>/dev/null; then
            warning "The application did not stop properly. Forcing shutdown..."
            kill -9 $pid
        fi
        success "The application has been stopped successfully."
    else
        port=$(grep "PORT=" .env | cut -d '=' -f2)
        pid=$(lsof -t -i:$port)
        if [ -n "$pid" ]; then
            info "Application found on port $port with PID: $pid"
            info "Stopping the application..."
            kill $pid
            sleep 2
            if kill -0 $pid 2>/dev/null; then
                warning "The application did not stop properly. Forcing shutdown..."
                kill -9 $pid
            fi
            success "The application has been stopped successfully."
        else
            warning "No running instance of the application was found."
        fi
    fi
}

update_env_and_restart() {
    clear_and_show_logo
    print_fancy_box "Update .env and Restart Application"

    choose_player
    ask_spotify_tokens

    port=$(grep "PORT=" .env | cut -d '=' -f2)

    cat << EOF > .env
PORT=$port
SPOTIFY_CLIENT_ID=$spotify_client_id
SPOTIFY_CLIENT_SECRET=$spotify_client_secret
PLAYERCTL_INSTANCE=$deezer_player
EOF
    success ".env file updated successfully."

    stop_app
    launch_app

    clear_and_show_logo
    print_fancy_box "Update Completed"
    success "The application has been updated and restarted on port $port."
    info "You can access the application at http://localhost:$port/now-playing"
    warning "Make sure Deezer is running when you use the application."

    echo
    read -p "Press Enter to return to the main menu..."
}

install_and_run() {
    clear_and_show_logo
    center_text "Installation and Configuration"
    echo

    print_fancy_box "Checking prerequisites"
    show_progress 2

    if ! command_exists playerctl; then
        if command_exists apt-get; then
            install_playerctl_debian
        elif command_exists dnf; then
            install_playerctl_redhat
        elif command_exists pacman; then
            install_playerctl_arch
        else
            error "Unable to detect a supported package manager."
            error "Please install playerctl manually for your distribution."
            exit 1
        fi
        if ! command_exists playerctl; then
            error "playerctl installation failed."
            exit 1
        fi
    fi

    clear_and_show_logo
    success "playerctl is installed."
    show_progress 1

    choose_player

    ask_spotify_tokens

    port=3000
    available_port=$(find_available_port $port)
    if [ $port -ne $available_port ]; then
        warning "Port $port is not available. Using port $available_port."
        port=$available_port
    fi

    cat << EOF > .env
PORT=$port
SPOTIFY_CLIENT_ID=$spotify_client_id
SPOTIFY_CLIENT_SECRET=$spotify_client_secret
PLAYERCTL_INSTANCE=$deezer_player
EOF
    success ".env file created successfully."

    install_dependencies

    build_app

    launch_app

    clear_and_show_logo
    print_fancy_box "Configuration completed"
    success "The application is now installed and running on port $port."
    info "You can access the application at http://localhost:$port/now-playing"
    warning "Make sure Deezer is running when you use the application."

    echo
    info "To stop the application later, rerun this script and choose option 2."

    echo
    read -p "Press Enter to return to the main menu..."
}

main() {
    while true; do
        clear_and_show_logo
        center_text "Now Playing Deezer - Installation and Management"
        echo

        print_fancy_box "Main Menu"
        echo -e "${CYAN}1.${RESET} Install and configure the application"
        echo -e "${CYAN}2.${RESET} Stop the application"
        echo -e "${CYAN}3.${RESET} Update .env and restart application"
        echo -e "${CYAN}4.${RESET} Quit"
        echo

        read -p "$(echo -e ${YELLOW}"Choose an option (1-4) : "${RESET})" choice

        case $choice in
            1)
                install_and_run
                ;;
            2)
                stop_app
                read -p "Press Enter to continue..."
                ;;
            3)
                update_env_and_restart
                ;;
            4)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                error "Invalid option. Please choose 1, 2, 3, or 4."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

main
