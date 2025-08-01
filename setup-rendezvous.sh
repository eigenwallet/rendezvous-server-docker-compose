#!/bin/bash

# Rendezvous Server Setup Wizard
# This script helps you set up a rendezvous point with proper configuration

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get local IP address
get_local_ip() {
    print_status "Detecting local IP address..."
    
    # Try multiple methods to get external IP
    local ip=""
    
    # Method 1: Using ipify.org
    if command_exists curl; then
        ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "")
    fi
    
    # Method 2: Using ifconfig.me as fallback
    if [[ -z "$ip" ]] && command_exists curl; then
        ip=$(curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || echo "")
    fi
    
    # Method 3: Using httpbin.org as another fallback
    if [[ -z "$ip" ]] && command_exists curl; then
        ip=$(curl -s --connect-timeout 5 https://httpbin.org/ip | grep -o '"origin":"[^"]*' | cut -d'"' -f4 2>/dev/null || echo "")
    fi
    
    # Method 4: Using wget if curl is not available
    if [[ -z "$ip" ]] && command_exists wget; then
        ip=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || echo "")
    fi
    
    if [[ -n "$ip" ]]; then
        print_success "Detected IP address: $ip"
        echo "$ip"
    else
        print_error "Failed to detect external IP address automatically"
        echo ""
    fi
}

# Function to validate domain points to IP
validate_domain() {
    local domain="$1"
    local expected_ip="$2"
    
    print_status "Validating domain $domain points to $expected_ip..."
    
    if ! command_exists dig && ! command_exists nslookup; then
        print_warning "Neither 'dig' nor 'nslookup' found. Cannot validate domain."
        return 1
    fi
    
    local resolved_ip=""
    
    # Try using dig first
    if command_exists dig; then
        resolved_ip=$(dig +short "$domain" A | head -n1 2>/dev/null || echo "")
    fi
    
    # Fallback to nslookup
    if [[ -z "$resolved_ip" ]] && command_exists nslookup; then
        resolved_ip=$(nslookup "$domain" 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}' || echo "")
    fi
    
    if [[ -z "$resolved_ip" ]]; then
        print_error "Failed to resolve domain $domain"
        return 1
    fi
    
    if [[ "$resolved_ip" == "$expected_ip" ]]; then
        print_success "Domain $domain correctly points to $expected_ip"
        return 0
    else
        print_error "Domain $domain points to $resolved_ip, but expected $expected_ip"
        return 1
    fi
}

# Function to monitor logs for peer ID
wait_for_peer_id() {
    local timeout=60
    local start_time=$(date +%s)
    
    print_status "Waiting for rendezvous server to start and generate peer ID..."
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            print_error "Timeout waiting for peer ID after ${timeout}s"
            return 1
        fi
        
        # Check if container is running
        if ! docker-compose ps | grep -q "rendezvous.*Up"; then
            print_error "Rendezvous container is not running"
            return 1
        fi
        
        # Look for peer ID in logs
        local peer_id=$(docker-compose logs rendezvous 2>/dev/null | grep -i "peer id\|peerid\|local peer id" | tail -n1 | grep -o "12D3KooW[A-Za-z0-9]*" || echo "")
        
        if [[ -n "$peer_id" ]]; then
            print_success "Found peer ID: $peer_id"
            echo "$peer_id"
            return 0
        fi
        
        echo -n "." >&2
        sleep 2
    done
}

# Main setup function
main() {
    echo "================================================================"
    echo "        Rendezvous Server Setup Wizard"
    echo "================================================================"
    echo
    
    # Check prerequisites
    print_status "Checking prerequisites..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command_exists docker-compose; then
        print_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
    echo
    
    # Step 1: Ask for port
    echo "Step 1: Port Configuration"
    echo "=========================="
    read -p "Enter the port for the rendezvous server (default: 8888): " user_port
    PORT=${user_port:-8888}
    
    # Validate port number
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
        print_error "Invalid port number: $PORT"
        exit 1
    fi
    
    print_success "Using port: $PORT"
    echo
    
    # Step 2: Write .env file
    echo "Step 2: Environment Configuration"
    echo "================================="
    print_status "Writing configuration to .env file..."
    
    cat > .env << EOF
RENDEZVOUS_PORT=$PORT
EOF
    
    print_success "Created .env file with RENDEZVOUS_PORT=$PORT"
    echo
    
    # Step 3: Get local IP
    echo "Step 3: IP Address Detection"
    echo "==========================="
    LOCAL_IP=$(get_local_ip)
    
    if [[ -z "$LOCAL_IP" ]]; then
        read -p "Please enter your external IP address manually: " LOCAL_IP
        if [[ -z "$LOCAL_IP" ]]; then
            print_error "IP address is required"
            exit 1
        fi
    fi
    echo
    
    # Step 4: Ask for domain and validate
    echo "Step 4: Domain Configuration"
    echo "==========================="
    read -p "Enter a domain that points to this machine (optional, press Enter to skip): " DOMAIN
    
    DOMAIN_VALID=false
    if [[ -n "$DOMAIN" ]]; then
        if validate_domain "$DOMAIN" "$LOCAL_IP"; then
            DOMAIN_VALID=true
        else
            print_warning "Domain validation failed, but continuing anyway..."
            read -p "Do you want to continue with this domain? (y/N): " continue_domain
            if [[ "$continue_domain" =~ ^[Yy]$ ]]; then
                DOMAIN_VALID=true
            else
                DOMAIN=""
            fi
        fi
    fi
    echo
    
    # Step 5: Start the service
    echo "Step 5: Starting Rendezvous Server"
    echo "=================================="
    print_status "Starting rendezvous server with docker-compose..."
    
    # Stop any existing container
    docker-compose down 2>/dev/null || true
    
    # Start the service
    if docker-compose up -d; then
        print_success "Rendezvous server started successfully"
    else
        print_error "Failed to start rendezvous server"
        exit 1
    fi
    echo
    
    # Step 6: Get peer ID from logs
    echo "Step 6: Peer ID Detection"
    echo "========================"
    PEER_ID=$(wait_for_peer_id)
    
    if [[ -z "$PEER_ID" ]]; then
        print_error "Failed to detect peer ID"
        print_warning "You can check the logs manually with: docker-compose logs rendezvous"
        exit 1
    fi
    echo
    
    # Step 7: Display multiaddresses
    echo "Step 7: Multiaddress Generation"
    echo "==============================="
    
    echo
    print_success "Setup completed successfully!"
    echo
    echo "================================================================"
    echo "               RENDEZVOUS SERVER INFORMATION"
    echo "================================================================"
    echo
    echo "Port: $PORT"
    echo "External IP: $LOCAL_IP"
    if [[ -n "$DOMAIN" ]]; then
        echo "Domain: $DOMAIN"
    fi
    echo "Peer ID: $PEER_ID"
    echo
    echo "Multiaddresses:"
    echo "---------------"
    
    # Generate multiaddresses
    echo "/ip4/$LOCAL_IP/tcp/$PORT/p2p/$PEER_ID"
    
    if [[ -n "$DOMAIN" && "$DOMAIN_VALID" == "true" ]]; then
        echo "/dns4/$DOMAIN/tcp/$PORT/p2p/$PEER_ID"
    fi
    
    echo
    echo "================================================================"
    echo
    print_status "You can view logs with: docker-compose logs -f rendezvous"
    print_status "To stop the server: docker-compose down"
    print_status "To restart the server: docker-compose up -d"
}

# Run the main function
main "$@"