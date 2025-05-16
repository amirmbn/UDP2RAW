CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m"
MAGENTA="\e[95m"
NC="\e[0m"

apt update -y && apt upgrade -y

press_enter() {
    echo -e "\n${RED}Press Enter to continue... ${NC}"
    read
}

display_fancy_progress() {
    local duration=$1
    local sleep_interval=0.1
    local progress=0
    local bar_length=40

    while [ $progress -lt $duration ]; do
        echo -ne "\r[${YELLOW}"
        for ((i = 0; i < bar_length; i++)); do
            if [ $i -lt $((progress * bar_length / duration)) ]; then
                echo -ne "▓"
            else
                echo -ne "░"
            fi
        done
        echo -ne "${RED}] ${progress}%${NC}"
        progress=$((progress + 1))
        sleep $sleep_interval
    done
    echo -ne "\r[${YELLOW}"
    for ((i = 0; i < bar_length; i++)); do
        echo -ne "#"
    done
    echo -ne "${RED}] ${progress}%${NC}"
    echo
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

install() {
    clear
    echo ""
    echo -e "${YELLOW}First, making sure that all packages are suitable for your server.${NC}"
    echo ""
    echo -e "Please wait, it might take a while"
    echo ""
    sleep 1
    secs=4
    while [ $secs -gt 0 ]; do
        echo -ne "Continuing in $secs seconds\033[0K\r"
        sleep 1
        : $((secs--))
    done
    echo ""
    apt-get update > /dev/null 2>&1
    display_fancy_progress 20
    echo ""
    system_architecture=$(uname -m)

    if [ "$system_architecture" != "x86_64" ] && [ "$system_architecture" != "amd64" ]; then
        echo -e "${RED}Unsupported architecture: $system_architecture${NC}"
        exit 1
    fi

    sleep 1
    echo ""
    echo -e "${YELLOW}Downloading and installing udp2raw for architecture: $system_architecture${NC}"
    
    # Download binaries with error handling
    if ! curl -L -o udp2raw_amd64 https://github.com/amirmbn/UDP2RAW/raw/main/Core/udp2raw_amd64; then
        echo -e "${RED}Failed to download udp2raw_amd64. Please check your internet connection.${NC}"
        return 1
    fi
    
    if ! curl -L -o udp2raw_x86 https://github.com/amirmbn/UDP2RAW/raw/main/Core/udp2raw_x86; then
        echo -e "${RED}Failed to download udp2raw_x86. Please check your internet connection.${NC}"
        return 1
    fi
    
    sleep 1

    chmod +x udp2raw_amd64
    chmod +x udp2raw_x86

    echo ""
    echo -e "${GREEN}Enabling IP forwarding...${NC}"
    display_fancy_progress 20
    
    # Check if forwarding is already enabled to avoid duplicate entries
    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
    
    if ! grep -q "net.ipv6.conf.all.forwarding = 1" /etc/sysctl.conf; then
        echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    fi
    
    sysctl -p > /dev/null 2>&1
    
    # Only reload ufw if it's installed and active
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw reload > /dev/null 2>&1
    fi
    
    echo ""
    echo -e "${GREEN}All packages were installed and configured.${NC}"
    return 0
}

validate_port() {
    local port="$1"
    
    # Check if port is a valid number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Port must be a number.${NC}"
        return 1
    fi
    
    # Check if port is in valid range
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}Port must be between 1-65535.${NC}"
        return 1
    fi
    
    # Check if port is used by WireGuard
    local wireguard_port=""
    if [ -d "/etc/wireguard" ]; then
        wireguard_port=$(awk -F'=' '/ListenPort/ {gsub(/ /,"",$2); print $2}' /etc/wireguard/*.conf 2>/dev/null)
        
        if [ "$port" -eq "$wireguard_port" ]; then
            echo -e "${RED}Port $port is already used by WireGuard. Please choose another port.${NC}"
            return 1
        fi
    fi

    # Check if port is in use
    if ss -tuln | grep -q ":$port "; then
        echo -e "${RED}Port $port is already in use. Please choose another port.${NC}"
        return 1
    fi

    return 0
}

remote_func() {
    clear
    echo ""
    echo -e "\e[33mSelect EU Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1)
            tunnel_mode="[::]"
            ;;
        2)
            tunnel_mode="0.0.0.0"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            remote_func
            return
            ;;
    esac

    while true; do
        echo -ne "\e[33mEnter the Local server (IR) port \e[92m[Default: 443]${NC}: "
        read local_port
        if [ -z "$local_port" ]; then
            local_port=443
            break
        fi
        if validate_port "$local_port"; then
            break
        fi
    done

    # Set the default WireGuard port without prompting
    remote_port=40600

    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[This will be used on your local server (IR)]${NC}: "
        read password
        if [ -z "$password" ]; then
            echo -e "${RED}Password cannot be empty. Please enter a password.${NC}"
        else
            break
        fi
    done
    
    echo ""
    echo -e "\e[33mProtocol (Mode) (Local and remote should be the same)${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}udp${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}faketcp${NC}"
    echo -e "${RED}3${NC}. ${YELLOW}icmp${NC}"
    echo ""
    echo -ne "Enter your choice [1-3] : ${NC}"
    read protocol_choice

    case $protocol_choice in
        1)
            raw_mode="udp"
            ;;
        2)
            raw_mode="faketcp"
            ;;
        3)
            raw_mode="icmp"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
            press_enter
            remote_func
            return
            ;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    # Create service file
    cat << EOF > /etc/systemd/system/udp2raw-s.service
[Unit]
Description=udp2raw-s Service
After=network.target

[Service]
ExecStart=/root/udp2raw_amd64 -s -l $tunnel_mode:${local_port} -r 127.0.0.1:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    # Start and enable service with error handling
    if ! systemctl restart "udp2raw-s.service"; then
        echo -e "${RED}Failed to start udp2raw-s service. Check the logs with: journalctl -u udp2raw-s.service${NC}"
        return 1
    fi
    
    if ! systemctl enable --now "udp2raw-s.service"; then
        echo -e "${RED}Failed to enable udp2raw-s service.${NC}"
        return 1
    fi
    
    sleep 1

    echo -e "\e[92mRemote Server (EU) configuration has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
}

local_func() {
    clear
    echo ""
    echo -e "\e[33mSelect IR Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1)
            tunnel_mode="IPV6"
            ;;
        2)
            tunnel_mode="IPV4"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            local_func
            return
            ;;
    esac
    
    while true; do
        echo -ne "\e[33mEnter the Local server (IR) port \e[92m[Default: 443]${NC}: "
        read remote_port
        if [ -z "$remote_port" ]; then
            remote_port=443
            break
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    while true; do
        echo ""
        echo -ne "\e[33mEnter the Wireguard port - installed on EU \e[92m[Default: 40600]${NC}: "
        read local_port
        if [ -z "$local_port" ]; then
            local_port=40600
            break
        fi
        if validate_port "$local_port"; then
            break
        fi
    done
    
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Remote server (EU) IPV6 / IPV4 (Based on your tunnel preference)\e[92m${NC}: "
        read remote_address
        if [ -z "$remote_address" ]; then
            echo -e "${RED}Remote address cannot be empty.${NC}"
        else
            break
        fi
    done
    
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[The same as you set on remote server (EU)]${NC}: "
        read password
        if [ -z "$password" ]; then
            echo -e "${RED}Password cannot be empty. Please enter a password.${NC}"
        else
            break
        fi
    done
    
    echo ""
    echo -e "\e[33mProtocol (Mode) \e[92m(Local and Remote should have the same value)${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}udp${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}faketcp${NC}"
    echo -e "${RED}3${NC}. ${YELLOW}icmp${NC}"
    echo ""
    echo -ne "Enter your choice [1-3] : ${NC}"
    read protocol_choice

    case $protocol_choice in
        1)
            raw_mode="udp"
            ;;
        2)
            raw_mode="faketcp"
            ;;
        3)
            raw_mode="icmp"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
            press_enter
            local_func
            return
            ;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    # Set the ExecStart command based on tunnel mode
    if [ "$tunnel_mode" == "IPV4" ]; then
        exec_start="/root/udp2raw_amd64 -c -l 0.0.0.0:${local_port} -r ${remote_address}:${remote_port} -k ${password} --raw-mode ${raw_mode} -a"
    else
        exec_start="/root/udp2raw_amd64 -c -l [::]:${local_port} -r [${remote_address}]:${remote_port} -k ${password} --raw-mode ${raw_mode} -a"
    fi

    # Create service file
    cat << EOF > /etc/systemd/system/udp2raw-c.service
[Unit]
Description=udp2raw-c Service
After=network.target

[Service]
ExecStart=${exec_start}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    # Start and enable service with error handling
    if ! systemctl restart "udp2raw-c.service"; then
        echo -e "${RED}Failed to start udp2raw-c service. Check the logs with: journalctl -u udp2raw-c.service${NC}"
        return 1
    fi
    
    if ! systemctl enable --now "udp2raw-c.service"; then
        echo -e "${RED}Failed to enable udp2raw-c service.${NC}"
        return 1
    fi

    echo -e "\e[92mLocal Server (IR) configuration has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
}

uninstall() {
    clear
    echo ""
    echo -e "${YELLOW}Uninstalling UDP2RAW, Please wait ...${NC}"
    echo ""
    echo ""
    display_fancy_progress 20

    # Stop and disable services
    systemctl stop "udp2raw-s.service" > /dev/null 2>&1
    systemctl disable "udp2raw-s.service" > /dev/null 2>&1
    systemctl stop "udp2raw-c.service" > /dev/null 2>&1
    systemctl disable "udp2raw-c.service" > /dev/null 2>&1
    
    # Remove service files and binaries
    rm -f /etc/systemd/system/udp2raw-s.service > /dev/null 2>&1
    rm -f /etc/systemd/system/udp2raw-c.service > /dev/null 2>&1
    rm -f /root/udp2raw_amd64 > /dev/null 2>&1
    rm -f /root/udp2raw_x86 > /dev/null 2>&1
    
    # Reload systemd
    systemctl daemon-reload > /dev/null 2>&1
    
    sleep 2
    echo ""
    echo ""
    echo -e "${GREEN}UDP2RAW has been uninstalled.${NC}"
}

menu_status() {
    systemctl is-active "udp2raw-s.service" &> /dev/null
    remote_status=$?

    systemctl is-active "udp2raw-c.service" &> /dev/null
    local_status=$?

    echo ""
    if [ $remote_status -eq 0 ]; then
        echo -e "\e[36m ${CYAN}EU Server Status${NC} > ${GREEN}Wireguard Tunnel is running.${NC}"
    else
        echo -e "\e[36m ${CYAN}EU Server Status${NC} > ${RED}Wireguard Tunnel is not running.${NC}"
    fi
    echo ""
    if [ $local_status -eq 0 ]; then
        echo -e "\e[36m ${CYAN}IR Server Status${NC} > ${GREEN}Wireguard Tunnel is running.${NC}"
    else
        echo -e "\e[36m ${CYAN}IR Server Status${NC} > ${RED}Wireguard Tunnel is not running.${NC}"
    fi
}

# Main menu loop
echo ""
while true; do
    clear    
    menu_status
    echo ""
    echo ""
    echo -e "\e[36m 1\e[0m) \e[93mInstall UDP2RAW binary"
    echo -e "\e[36m 2\e[0m) \e[93mSet EU Tunnel"
    echo -e "\e[36m 3\e[0m) \e[93mSet IR Tunnel"  
    echo ""
    echo -e "\e[36m 4\e[0m) \e[93mUninstall UDP2RAW"
    echo -e "\e[36m 0\e[0m) \e[93mExit"
    echo ""
    echo ""
    echo -ne "\e[92mSelect an option \e[31m[\e[97m0-4\e[31m]: \e[0m"
    read choice

    case $choice in
        1)
            install
            ;;
        2)
            remote_func
            ;;
        3)
            local_func
            ;;
        4)
            uninstall
            ;;
        0)
            echo -e "\n ${RED}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "\n ${RED}Invalid choice. Please enter a valid option.${NC}"
            ;;
    esac

    press_enter
done
