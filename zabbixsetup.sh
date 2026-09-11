#!/bin/bash
#########################################################################
# Zabbix Agent Management Script                                        #
# Last Updated: 06-01-2026                                              #
#                                                                       #
# Written, Updated and Maintained by: Matt Hodges                       #
# (matt.hodges@thgingenuity.com)                                        #
#                                                                       #
# For issues, bugs, improvements, or collaborations, contact:           #
# Cloud and Infrastructure Support DL (DL-CIsupport@thehutgroup.com)    #
#########################################################################

# Set up some color variables for improved readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Base directory
BASEDIR="/home/L3/zabbix_ansible_modernised"

# Log directory setup
LOGDIR="${BASEDIR}/logs"
mkdir -p "$LOGDIR"
find "$LOGDIR" -type f -name "zabbix_*.log" -mtime +14 -delete 2>/dev/null

# Pre-flight checks
preflight_check() {
    local errors=0
    
    # Check vault password file
    if [[ ! -f /home/L3/.vault_pass ]]; then
        echo -e "${RED}ERROR: Vault password file not found at /home/L3/.vault_pass${NC}"
        ((errors++))
    fi
    
    # Check SSH key for managed servers
    if [[ ! -f "${BASEDIR}/id_rsa_managed.pub" ]]; then
        echo -e "${RED}ERROR: SSH public key not found at ${BASEDIR}/id_rsa_managed.pub${NC}"
        ((errors++))
    fi
    
    # Check playbooks exist
    if [[ ! -f "${BASEDIR}/playbooks/zabbix_agent.yml" ]]; then
        echo -e "${RED}ERROR: Install playbook not found at ${BASEDIR}/playbooks/zabbix_agent.yml${NC}"
        ((errors++))
    fi
    
    if [[ ! -f "${BASEDIR}/playbooks/zabbix_remove.yml" ]]; then
        echo -e "${YELLOW}WARNING: Remove playbook not found at ${BASEDIR}/playbooks/zabbix_remove.yml${NC}"
        echo -e "${YELLOW}         Removal functionality will not be available.${NC}"
    fi
    
    # Check passwords file
    if [[ ! -f "${BASEDIR}/config/passwords" ]]; then
        echo -e "${RED}ERROR: Passwords file not found at ${BASEDIR}/config/passwords${NC}"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}Pre-flight check failed. Please fix the above errors before continuing.${NC}"
        exit 1
    fi
}

# =============================================================================
# MAIN MENU
# =============================================================================

function mainMenu() {
    clear
    echo -e "${GREEN}\t################### Zabbix Management ###################${NC}\n"
    echo -e "Choose an action:\n"
    echo -e "1. ${GREEN}Install${NC}      - Add server to Zabbix monitoring"
    echo -e "2. ${YELLOW}Update${NC}       - Change server brand/group/template"
    echo -e "3. ${CYAN}Edit${NC}         - Edit host details (owner email, SSH port)"
    echo -e "4. ${CYAN}Fix Firewall${NC} - Fix Zabbix agent connectivity (add FW rule)"
    echo -e "5. ${RED}Uninstall${NC}    - Uninstall Zabbix agent from server"
    echo -e "6. ${RED}Remove${NC}       - Remove server from Zabbix (API only)"
    echo -e "7. Exit"
    echo -e "\nYour choice:"
    read -r action
    case $action in
        1) installFlow ;;
        2) updateFlow ;;
        3) editFlow ;;
        4) fixFirewallFlow ;;
        5) uninstallAgentFlow ;;
        6) removeFlow ;;
        7) echo -e "${YELLOW}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice, please try again.${NC}"; sleep 1; mainMenu ;;
    esac
}

# =============================================================================
# INSTALL FLOW
# =============================================================================

function installFlow() {
    grSelect
    serverTypeSelect
    getServerDetails
    reviewInstall
    confirmInstall
}

function grSelect() {
    clear
    force_openstack=false
    echo -e "${GREEN}################### Zabbix Group Selection ###################${NC}\n"
    echo -e "Choose an option:\n"
    echo -e "1. VPS.NET Monitoring"
    echo -e "2. VPS.NET Configuration (Ultimate Support)"
    echo -e "3. ICS (100TB)"
    echo -e "4. UK2"
    echo -e "5. Midphase"
    echo -e "6. Westhost"
    echo -e "7. ${CYAN}Fabrc${NC} (OpenStack)"
    echo -e "\nYour choice:"
    read -r zgroup
    case $zgroup in
        1)
          extra_vars="zabbix_agent_hostname=Mon_{{ inventory_hostname }} zabbix_host_groups='L3-MONITORING_SUPPORT' zabbix_link_templates='Template Ultimate Support'"
          hostname_prefix="Mon_"
          ;;
        2)
          extra_vars="zabbix_agent_hostname=Ult_{{ inventory_hostname }} zabbix_host_groups='L3-MANAGED_SUPPORT' zabbix_link_templates='Template Ultimate Support'"
          hostname_prefix="Ult_"
          ;;
        3)
          extra_vars="zabbix_agent_hostname=100TB_{{ inventory_hostname }} zabbix_host_groups='L3-TOUCH_SUPPORT' zabbix_link_templates='Template Touch Support'"
          hostname_prefix="100TB_"
          ;;
        4)
          extra_vars="zabbix_agent_hostname=UK2_{{ inventory_hostname }} zabbix_host_groups='L3-TOUCH_SUPPORT' zabbix_link_templates='Template Touch Support'"
          hostname_prefix="UK2_"
          ;;
        5)
          extra_vars="zabbix_agent_hostname=MP_{{ inventory_hostname }} zabbix_host_groups='L3-TOUCH_SUPPORT' zabbix_link_templates='Template Touch Support'"
          hostname_prefix="MP_"
          ;;
        6)
          extra_vars="zabbix_agent_hostname=WH_{{ inventory_hostname }} zabbix_host_groups='L3-TOUCH_SUPPORT' zabbix_link_templates='Template Touch Support'"
          hostname_prefix="WH_"
          ;;
        7)
          extra_vars="zabbix_agent_hostname=FABRC_{{ inventory_hostname }} zabbix_host_groups='L3-FABRC_SUPPORT' zabbix_link_templates='Template Ultimate Support'"
          hostname_prefix="FABRC_"
          force_openstack=true
          echo -e "\n${CYAN}Fabrc is OpenStack-only - using OpenStack configuration.${NC}"
          ;;
        *)
          echo -e "${RED}Invalid choice, please try again.${NC}"
          grSelect
          ;;
    esac
}

function serverTypeSelect() {
    # If Fabrc selected, skip menu and go straight to OpenStack
    if [[ "$force_openstack" == "true" ]]; then
        echo -e "\n${CYAN}OpenStack default users by distro:${NC}"
        echo -e "  - Rocky Linux:    rocky"
        echo -e "  - AlmaLinux:      almalinux"
        echo -e "  - CentOS:         centos, cloud-user"
        echo -e "  - Ubuntu:         ubuntu"
        echo -e "  - Debian:         debian"
        echo -e "\nEnter SSH user:"
        read -r sshuser
        if [[ -z "$sshuser" ]]; then
            echo -e "${RED}SSH user is required for OpenStack instances.${NC}"
            serverTypeSelect
            return
        fi
        authmethod="key"
        selectSSHKey
        return
    fi

    echo -e "\n${GREEN}################### Server Type ###################${NC}\n"
    echo -e "Choose the server type:\n"
    echo -e "1. Traditional Server (root user, password auth)"
    echo -e "2. Traditional Server (root user, key already deployed)"
    echo -e "3. OpenStack Instance (non-root user, SSH key auth)"
    echo -e "4. Custom (specify user and auth method)"
    echo -e "\nYour choice:"
    read -r servertype
    case $servertype in
        1)
          sshuser="root"
          authmethod="password"
          ;;
        2)
          sshuser="root"
          authmethod="key"
          # Use shared L3 key
          sshkey="/home/L3/.ssh/ultimate_support_key"
          ;;
        3)
          echo -e "\n${CYAN}OpenStack default users by distro:${NC}"
          echo -e "  - Rocky Linux:    rocky"
          echo -e "  - AlmaLinux:      almalinux"
          echo -e "  - CentOS:         centos, cloud-user"
          echo -e "  - Ubuntu:         ubuntu"
          echo -e "  - Debian:         debian"
          echo -e "\nEnter SSH user:"
          read -r sshuser
          if [[ -z "$sshuser" ]]; then
              echo -e "${RED}SSH user is required for OpenStack instances.${NC}"
              serverTypeSelect
              return
          fi
          authmethod="key"
          selectSSHKey
          ;;
        4)
          echo -e "\nEnter SSH user (default: root):"
          read -r sshuser
          sshuser=${sshuser:-root}
          selectAuthMethod
          ;;
        *)
          echo -e "${RED}Invalid choice, please try again.${NC}"
          serverTypeSelect
          ;;
    esac
}

function selectAuthMethod() {
    echo -e "\n${GREEN}############## Authentication Method ##############${NC}\n"
    echo -e "Choose authentication method:\n"
    echo -e "1. Password"
    echo -e "2. SSH Key"
    echo -e "\nYour choice:"
    read -r authchoice
    case $authchoice in
        1)
          authmethod="password"
          ;;
        2)
          authmethod="key"
          selectSSHKey
          ;;
        *)
          echo -e "${RED}Invalid choice, please try again.${NC}"
          selectAuthMethod
          ;;
    esac
}

function selectSSHKey() {
    echo -e "\n${GREEN}################# SSH Key Selection #################${NC}\n"
    
    # List available keys in shared L3 location only
    echo -e "Available SSH keys:\n"
    local keycount=0
    declare -a keylist
    
    # Check shared L3 location
    for keyfile in /home/L3/.ssh/*_key /home/L3/.ssh/*-key /home/L3/.ssh/*.pem /home/L3/.ssh/id_*; do
        if [[ -f "$keyfile" && ! "$keyfile" =~ \.pub$ ]]; then
            ((keycount++))
            keylist+=("$keyfile")
            echo -e "  ${keycount}. $keyfile"
        fi
    done
    
    if [[ $keycount -eq 0 ]]; then
        echo -e "${RED}No shared SSH keys found in /home/L3/.ssh/${NC}"
        echo -e "Please contact your administrator."
        exit 1
    fi
    
    echo -e "\n  c. Enter custom path"
    echo -e "\nSelect key (number) or enter full path:"
    read -r keychoice
    
    # Check if it's a number corresponding to the list
    if [[ "$keychoice" =~ ^[0-9]+$ ]] && [[ $keychoice -le $keycount ]] && [[ $keychoice -gt 0 ]]; then
        sshkey="${keylist[$((keychoice-1))]}"
    else
        # Assume it's a path
        sshkey="$keychoice"
    fi
    
    # Validate key exists
    if [[ ! -f "$sshkey" ]]; then
        echo -e "${RED}SSH key not found: $sshkey${NC}"
        echo -e "Please try again."
        selectSSHKey
        return
    fi
    
    echo -e "${GREEN}Selected key:${NC} $sshkey"
}

function getServerDetails() {
    echo -e "\n${GREEN}############### Server's IP Address ###############${NC}"
    echo -e "Enter server's IP address:"
    read -r ipaddr
    validate_ip

    echo -e "\n${GREEN}################ Server's SSH Port ################${NC}"
    echo -e "Enter server's SSH port (default: 22):"
    read -r sshport
    sshport=${sshport:-22}

    echo -e "\n${GREEN}############ Server's Owner Email Address ##########${NC}"
    echo -e "Enter owner's email address:"
    read -r mailaddr
    validate_email
}

# Validate IP format
function validate_ip() {
    if [[ ! $ipaddr =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Invalid IP address format. Please try again.${NC}"
        read -r ipaddr
        validate_ip
    fi
}

# Validate email format
function validate_email() {
    if [[ ! $mailaddr =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
        echo -e "${RED}Invalid email format. Please try again.${NC}"
        read -r mailaddr
        validate_email
    fi
}

function reviewInstall() {
    echo -e "\n${GREEN}------------------- Review Information -------------------${NC}"
    echo -e "${GREEN}Server IP:${NC} $ipaddr"
    echo -e "${GREEN}SSH Port:${NC} $sshport"
    echo -e "${GREEN}SSH User:${NC} $sshuser"
    echo -e "${GREEN}Auth Method:${NC} $authmethod"
    if [[ "$authmethod" == "key" ]]; then
        echo -e "${GREEN}SSH Key:${NC} $sshkey"
    fi
    if [[ "$sshuser" != "root" ]]; then
        echo -e "${GREEN}Privilege Escalation:${NC} sudo (become)"
    fi
    echo -e "${GREEN}Owner Email:${NC} $mailaddr"
    echo -e "${GREEN}Zabbix Hostname:${NC} ${hostname_prefix}${ipaddr}"
    echo -e "${GREEN}------------------------------------------------------------${NC}"
}

function confirmInstall() {
    echo -e "\nDo you want to proceed with the Zabbix installation? (y/n)"
    read -r des
    if [[ $des == "y" ]]; then
        showContactInfo
        runInstallPlaybook
    elif [[ $des == "n" ]]; then
        echo -e "${RED}Operation cancelled.${NC}"
        exit 0
    else
        echo -e "${RED}Invalid input, please enter 'y' or 'n'.${NC}"
        confirmInstall
    fi
}

function showContactInfo() {
    echo -e "${GREEN}\n------------------- Contact Information -------------------${NC}"
    echo -e "${GREEN}For issues, bugs, improvements, or collaborations, please contact:${NC}"
    echo -e "Name: ${GREEN}Matt Hodges${NC}"
    echo -e "Email: ${GREEN}matt.hodges@thgingenuity.com${NC}"
    echo -e "Teams: ${GREEN}Reach out via direct message or via Hosting Support Channels.${NC}"
    echo -e "Cloud and Infrastructure Support DL: ${GREEN}DL-CIsupport@thehutgroup.com${NC}\n"
    echo -e "${GREEN}Internal Confluence Documentation:${NC}"
    echo -e "1. Ultimate Support Monitoring Configuration: https://thehut.atlassian.net/wiki/spaces/VPSNET/pages/1062208054"
    echo -e "2. Adding Zabbix Monitoring (100TB): https://thehut.atlassian.net/wiki/spaces/100TB/pages/557842756"
    echo -e "\n#############################################################\n"
}

function runInstallPlaybook() {
    LOGFILE="${LOGDIR}/zabbix_install_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${YELLOW}Starting the Zabbix installation. This may take a few moments...${NC}"
    cd "$BASEDIR" || exit

    # Build the base command
    local cmd="ansible-playbook playbooks/zabbix_agent.yml"
    cmd+=" -u $sshuser"
    cmd+=" -i '$ipaddr,'"
    cmd+=" --vault-password-file /home/L3/.vault_pass"
    
    # Add authentication method
    if [[ "$authmethod" == "password" ]]; then
        cmd+=" -k"
    else
        cmd+=" --private-key '$sshkey'"
    fi
    
    # Add become if not root
    if [[ "$sshuser" != "root" ]]; then
        cmd+=" --become"
        cmd+=" --become-method sudo"
        cmd+=" --become-user root"
    fi
    
    # Add extra vars
    cmd+=" -e \"ansible_port=$sshport owner_email='$mailaddr' $extra_vars\""
    
    # Show command being run (for debugging)
    echo -e "\n${CYAN}Running:${NC}"
    echo -e "$cmd\n"
    
    # Execute
    eval "$cmd" 2>&1 | tee "$LOGFILE"
    
    playbook_status=${PIPESTATUS[0]}
    
    # Check if the playbook succeeded
    if [[ $playbook_status -eq 0 ]]; then
        echo -e "${GREEN}Zabbix installation completed successfully!${NC}"
        echo -e "${GREEN}Logs saved to:${NC} $LOGFILE"
    else
        echo -e "${RED}Zabbix installation failed.${NC}"
        handleInstallError
    fi
}

function handleInstallError() {
    if grep -q "No supported firewall" "$LOGFILE"; then
        echo -e "${RED}Firewall configuration failed. No supported firewall detected.${NC}"
    elif grep -q "TASK \[Configure zabbix-agent\] .* failed" "$LOGFILE"; then
        echo -e "${RED}Zabbix agent configuration failed. Please check the logs for further details.${NC}"
    elif grep -q "TASK \[Create hostgroups\] .* failed" "$LOGFILE"; then
        echo -e "${RED}Zabbix API call to create hostgroups failed. Please verify API access and credentials.${NC}"
    elif grep -q "UNREACHABLE" "$LOGFILE"; then
        echo -e "${RED}Could not connect to host. Check IP address, SSH port, and credentials.${NC}"
    elif grep -q "Permission denied" "$LOGFILE"; then
        echo -e "${RED}Authentication failed. Check password or SSH key.${NC}"
    elif grep -q "sudo: a password is required" "$LOGFILE"; then
        echo -e "${RED}Sudo requires a password on this host. May need to configure NOPASSWD or use -K flag.${NC}"
    else
        echo -e "${RED}An unknown error occurred. Please check the logs for more details: ${NC}$LOGFILE"
    fi
}

# =============================================================================
# UPDATE FLOW
# =============================================================================

function updateFlow() {
    clear
    echo -e "${YELLOW}################### Update Zabbix Host ###################${NC}\n"
    
    # Check if update playbook exists
    if [[ ! -f "${BASEDIR}/playbooks/zabbix_update.yml" ]]; then
        echo -e "${RED}ERROR: Update playbook not found at ${BASEDIR}/playbooks/zabbix_update.yml${NC}"
        echo -e "Please ensure the playbook exists before attempting update."
        exit 1
    fi
    
    echo -e "This will update a host's brand, group, and template in Zabbix."
    echo -e "${CYAN}Note: This is an API-only operation - no changes are made to the server.${NC}\n"
    
    getUpdateDetails
    selectNewBrand
    reviewUpdate
    confirmUpdate
}

function getUpdateDetails() {
    echo -e "${GREEN}Enter the current Zabbix hostname:${NC}"
    echo -e "${CYAN}(e.g., Mon_192.168.1.100, 100TB_10.0.0.50, UK2_203.0.113.25)${NC}"
    echo -e "\nCurrent hostname:"
    read -r current_hostname
    
    if [[ -z "$current_hostname" ]]; then
        echo -e "${RED}Hostname is required.${NC}"
        getUpdateDetails
        return
    fi
    
    # Extract IP from hostname for new hostname generation
    host_ip=$(echo "$current_hostname" | sed 's/^[^_]*_//')
}

function selectNewBrand() {
    echo -e "\n${GREEN}################### Select New Brand ###################${NC}\n"
    echo -e "Choose the new brand/group:\n"
    echo -e "1. VPS.NET Monitoring"
    echo -e "2. VPS.NET Configuration (Ultimate Support)"
    echo -e "3. ICS (100TB)"
    echo -e "4. UK2"
    echo -e "5. Midphase"
    echo -e "6. Westhost"
    echo -e "7. ${CYAN}Fabrc${NC}"
    echo -e "\nYour choice:"
    read -r newbrand
    case $newbrand in
        1)
          new_hostname="Mon_${host_ip}"
          new_host_groups="L3-MONITORING_SUPPORT"
          new_link_templates="Template Ultimate Support"
          ;;
        2)
          new_hostname="Ult_${host_ip}"
          new_host_groups="L3-MANAGED_SUPPORT"
          new_link_templates="Template Ultimate Support"
          ;;
        3)
          new_hostname="100TB_${host_ip}"
          new_host_groups="L3-TOUCH_SUPPORT"
          new_link_templates="Template Touch Support"
          ;;
        4)
          new_hostname="UK2_${host_ip}"
          new_host_groups="L3-TOUCH_SUPPORT"
          new_link_templates="Template Touch Support"
          ;;
        5)
          new_hostname="MP_${host_ip}"
          new_host_groups="L3-TOUCH_SUPPORT"
          new_link_templates="Template Touch Support"
          ;;
        6)
          new_hostname="WH_${host_ip}"
          new_host_groups="L3-TOUCH_SUPPORT"
          new_link_templates="Template Touch Support"
          ;;
        7)
          new_hostname="FABRC_${host_ip}"
          new_host_groups="L3-FABRC_SUPPORT"
          new_link_templates="Template Ultimate Support"
          ;;
        *)
          echo -e "${RED}Invalid choice, please try again.${NC}"
          selectNewBrand
          ;;
    esac
}

function reviewUpdate() {
    echo -e "\n${YELLOW}------------------- Review Update -------------------${NC}"
    echo -e "${GREEN}Current Hostname:${NC} $current_hostname"
    echo -e "${GREEN}New Hostname:${NC} $new_hostname"
    echo -e "${GREEN}New Host Group:${NC} $new_host_groups"
    echo -e "${GREEN}New Template:${NC} $new_link_templates"
    echo -e "${YELLOW}-----------------------------------------------------${NC}"
}

function confirmUpdate() {
    echo -e "\n${YELLOW}Do you want to proceed with this update? (y/n)${NC}"
    read -r confirm
    if [[ $confirm == "y" || $confirm == "yes" ]]; then
        runUpdatePlaybook
    elif [[ $confirm == "n" || $confirm == "no" ]]; then
        echo -e "${YELLOW}Update cancelled.${NC}"
        exit 0
    else
        echo -e "${RED}Invalid input, please enter 'y' or 'n'.${NC}"
        confirmUpdate
    fi
}

function runUpdatePlaybook() {
    LOGFILE="${LOGDIR}/zabbix_update_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${YELLOW}Updating host in Zabbix. This may take a moment...${NC}"
    cd "$BASEDIR" || exit

    # Build the command - API only, runs on localhost
    local cmd="ansible-playbook playbooks/zabbix_update.yml"
    cmd+=" --vault-password-file /home/L3/.vault_pass"
    cmd+=" -e \"zabbix_agent_hostname='$current_hostname' new_hostname='$new_hostname' new_host_groups='$new_host_groups' new_link_templates='$new_link_templates'\""
    
    # Show command being run
    echo -e "\n${CYAN}Running:${NC}"
    echo -e "$cmd\n"
    
    # Execute
    eval "$cmd" 2>&1 | tee "$LOGFILE"
    
    playbook_status=${PIPESTATUS[0]}
    
    if [[ $playbook_status -eq 0 ]]; then
        echo -e "${GREEN}Host updated successfully!${NC}"
        echo -e "${GREEN}Logs saved to:${NC} $LOGFILE"
    else
        echo -e "${RED}Update failed. Please check the logs: ${NC}$LOGFILE"
    fi
}

# =============================================================================
# EDIT FLOW
# =============================================================================

function editFlow() {
    clear
    echo -e "${CYAN}################### Edit Zabbix Host Details ###################${NC}\n"
    
    # Check if edit playbook exists
    if [[ ! -f "${BASEDIR}/playbooks/zabbix_edit_macro.yml" ]]; then
        echo -e "${RED}ERROR: Edit playbook not found at ${BASEDIR}/playbooks/zabbix_edit_macro.yml${NC}"
        echo -e "Please ensure the playbook exists before attempting edit."
        exit 1
    fi
    
    echo -e "This will edit host macros (owner email, SSH port, etc.) in Zabbix."
    echo -e "${CYAN}Note: This is an API-only operation - no changes are made to the server.${NC}\n"
    
    getEditHostname
    selectMacroToEdit
    getNewMacroValue
    reviewEdit
    confirmEdit
}

function getEditHostname() {
    echo -e "${GREEN}Enter the Zabbix hostname to edit:${NC}"
    echo -e "${CYAN}(e.g., Mon_192.168.1.100, 100TB_109.123.108.169)${NC}"
    echo -e "\nHostname:"
    read -r edit_hostname
    
    if [[ -z "$edit_hostname" ]]; then
        echo -e "${RED}Hostname is required.${NC}"
        getEditHostname
        return
    fi
}

function selectMacroToEdit() {
    echo -e "\n${GREEN}################### Select Field to Edit ###################${NC}\n"
    echo -e "Choose what to edit:\n"
    echo -e "1. Owner Email"
    echo -e "2. SSH Port"
    echo -e "3. Custom Macro"
    echo -e "\nYour choice:"
    read -r macro_choice
    case $macro_choice in
        1)
          macro_key="OWNER_EMAIL"
          macro_friendly="Owner Email"
          ;;
        2)
          macro_key="SSH_PORT"
          macro_friendly="SSH Port"
          ;;
        3)
          echo -e "\nEnter macro name (without \$):"
          read -r macro_key
          macro_friendly="$macro_key"
          ;;
        *)
          echo -e "${RED}Invalid choice, please try again.${NC}"
          selectMacroToEdit
          ;;
    esac
}

function getNewMacroValue() {
    echo -e "\n${GREEN}Enter new value for ${macro_friendly}:${NC}"
    read -r macro_value
    
    if [[ -z "$macro_value" ]]; then
        echo -e "${RED}Value cannot be empty.${NC}"
        getNewMacroValue
        return
    fi
}

function reviewEdit() {
    echo -e "\n${YELLOW}------------------- Review Edit -------------------${NC}"
    echo -e "${GREEN}Hostname:${NC} $edit_hostname"
    echo -e "${GREEN}Field:${NC} $macro_friendly"
    echo -e "${GREEN}New Value:${NC} $macro_value"
    echo -e "${YELLOW}---------------------------------------------------${NC}"
}

function confirmEdit() {
    echo -e "\n${YELLOW}Do you want to apply this edit? (y/n)${NC}"
    read -r confirm
    if [[ $confirm == "y" || $confirm == "yes" ]]; then
        runEditPlaybook
    elif [[ $confirm == "n" || $confirm == "no" ]]; then
        echo -e "${YELLOW}Edit cancelled.${NC}"
        exit 0
    else
        echo -e "${RED}Invalid input, please enter 'y' or 'n'.${NC}"
        confirmEdit
    fi
}

function runEditPlaybook() {
    LOGFILE="${LOGDIR}/zabbix_edit_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${YELLOW}Updating host in Zabbix. This may take a moment...${NC}"
    cd "$BASEDIR" || exit

    # Build the command - API only, runs on localhost
    local cmd="ansible-playbook playbooks/zabbix_edit_macro.yml"
    cmd+=" --vault-password-file /home/L3/.vault_pass"
    cmd+=" -e \"zabbix_agent_hostname='$edit_hostname' macro_key='$macro_key' macro_value='$macro_value'\""
    
    # Show command being run
    echo -e "\n${CYAN}Running:${NC}"
    echo -e "$cmd\n"
    
    # Execute
    eval "$cmd" 2>&1 | tee "$LOGFILE"
    
    playbook_status=${PIPESTATUS[0]}
    
    if [[ $playbook_status -eq 0 ]]; then
        echo -e "${GREEN}Host macro updated successfully!${NC}"
        echo -e "${GREEN}Logs saved to:${NC} $LOGFILE"
        
        # Offer to edit another field
        echo -e "\n${YELLOW}Would you like to edit another field on this host? (y/n)${NC}"
        read -r edit_another
        if [[ $edit_another == "y" ]]; then
            selectMacroToEdit
            getNewMacroValue
            reviewEdit
            confirmEdit
        fi
    else
        echo -e "${RED}Edit failed. Please check the logs: ${NC}$LOGFILE"
    fi
}

# =============================================================================
# FIX FIREWALL FLOW
# =============================================================================

function fixFirewallFlow() {
    clear
    echo -e "${CYAN}################### Fix Zabbix Firewall Rules ###################${NC}\n"
    
    # Check if fix firewall playbook exists
    if [[ ! -f "${BASEDIR}/playbooks/zabbix_fix_firewall.yml" ]]; then
        echo -e "${RED}ERROR: Fix firewall playbook not found at ${BASEDIR}/playbooks/zabbix_fix_firewall.yml${NC}"
        echo -e "Please ensure the playbook exists before attempting this operation."
        exit 1
    fi
    
    echo -e "This will add firewall rules to allow the Zabbix proxy to connect."
    echo -e "${CYAN}Use this when the agent is installed but showing 'unreachable' in Zabbix.${NC}\n"
    
    getFirewallFixDetails
    reviewFirewallFix
    confirmFirewallFix
}

function getFirewallFixDetails() {
    echo -e "${GREEN}############### Server's IP Address ###############${NC}"
    echo -e "Enter server's IP address:"
    read -r ipaddr
    validate_ip
    
    echo -e "\n${GREEN}################ Server's SSH Port ################${NC}"
    echo -e "Enter server's SSH port (default: 22):"
    read -r sshport
    sshport=${sshport:-22}
    
    serverTypeSelectForFix
}

function serverTypeSelectForFix() {
    echo -e "\n${GREEN}################### Server Type ###################${NC}\n"
    echo -e "Choose the server type:\n"
    echo -e "1. Traditional Server (root user, key already deployed)"
    echo -e "2. Traditional Server (root user, password auth)"
    echo -e "3. OpenStack Instance (non-root user, SSH key)"
    echo -e "4. Custom (specify user and auth method)"
    echo -e "\nYour choice:"
    read -r servertype
    case $servertype in
        1)
          sshuser="root"
          authmethod="key"
          # Use shared L3 key
          sshkey="/home/L3/.ssh/ultimate_support_key"
          ;;
        2)
          sshuser="root"
          authmethod="password"
          ;;
        3)
          echo -e "\n${CYAN}OpenStack default users by distro:${NC}"
          echo -e "  - Rocky Linux:    rocky"
          echo -e "  - AlmaLinux:      almalinux"
          echo -e "  - CentOS:         centos, cloud-user"
          echo -e "  - Ubuntu:         ubuntu"
          echo -e "  - Debian:         debian"
          echo -e "\nEnter SSH user:"
          read -r sshuser
          if [[ -z "$sshuser" ]]; then
              echo -e "${RED}SSH user is required for OpenStack instances.${NC}"
              serverTypeSelectForFix
              return
          fi
          authmethod="key"
          selectSSHKey
          ;;
        4)
          echo -e "\nEnter SSH user (default: root):"
          read -r sshuser
          sshuser=${sshuser:-root}
          selectAuthMethod
          ;;
        *)
          echo -e "${RED}Invalid choice, please try again.${NC}"
          serverTypeSelectForFix
          ;;
    esac
}

function reviewFirewallFix() {
    echo -e "\n${YELLOW}------------------- Review Firewall Fix -------------------${NC}"
    echo -e "${GREEN}Server IP:${NC} $ipaddr"
    echo -e "${GREEN}SSH Port:${NC} $sshport"
    echo -e "${GREEN}SSH User:${NC} $sshuser"
    echo -e "${GREEN}Auth Method:${NC} $authmethod"
    if [[ "$authmethod" == "key" ]]; then
        echo -e "${GREEN}SSH Key:${NC} $sshkey"
    fi
    echo -e "${GREEN}Action:${NC} Add firewall rule for Zabbix proxy (109.123.125.234:10050)"
    echo -e "${YELLOW}-----------------------------------------------------------${NC}"
}

function confirmFirewallFix() {
    echo -e "\n${YELLOW}Do you want to proceed with the firewall fix? (y/n)${NC}"
    read -r confirm
    if [[ $confirm == "y" || $confirm == "yes" ]]; then
        runFirewallFixPlaybook
    elif [[ $confirm == "n" || $confirm == "no" ]]; then
        echo -e "${YELLOW}Firewall fix cancelled.${NC}"
        exit 0
    else
        echo -e "${RED}Invalid input, please enter 'y' or 'n'.${NC}"
        confirmFirewallFix
    fi
}

function runFirewallFixPlaybook() {
    LOGFILE="${LOGDIR}/zabbix_fix_firewall_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${YELLOW}Fixing firewall rules. This may take a few moments...${NC}"
    cd "$BASEDIR" || exit

    # Build the command
    local cmd="ansible-playbook playbooks/zabbix_fix_firewall.yml"
    cmd+=" -u $sshuser"
    cmd+=" -i '$ipaddr,'"
    
    # Add authentication method
    if [[ "$authmethod" == "password" ]]; then
        cmd+=" -k"
    else
        cmd+=" --private-key '$sshkey'"
    fi
    
    # Add become if not root
    if [[ "$sshuser" != "root" ]]; then
        cmd+=" --become"
        cmd+=" --become-method sudo"
        cmd+=" --become-user root"
    fi
    
    cmd+=" -e \"ansible_port=$sshport\""
    
    # Show command being run
    echo -e "\n${CYAN}Running:${NC}"
    echo -e "$cmd\n"
    
    # Execute
    eval "$cmd" 2>&1 | tee "$LOGFILE"
    
    playbook_status=${PIPESTATUS[0]}
    
    if [[ $playbook_status -eq 0 ]]; then
        echo -e "${GREEN}Firewall rules fixed successfully!${NC}"
        echo -e "${GREEN}Logs saved to:${NC} $LOGFILE"
        echo -e "\n${CYAN}The Zabbix proxy should now be able to connect. Check Zabbix in a few minutes.${NC}"
    else
        echo -e "${RED}Firewall fix failed. Please check the logs: ${NC}$LOGFILE"
    fi
}

# =============================================================================
# UNINSTALL AGENT FLOW
# =============================================================================

function uninstallAgentFlow() {
    clear
    echo -e "${RED}################### Uninstall Zabbix Agent ###################${NC}\n"
    
    # Check if uninstall playbook exists
    if [[ ! -f "${BASEDIR}/playbooks/zabbix_uninstall_agent.yml" ]]; then
        echo -e "${RED}ERROR: Uninstall playbook not found at ${BASEDIR}/playbooks/zabbix_uninstall_agent.yml${NC}"
        echo -e "Please ensure the playbook exists before attempting uninstall."
        exit 1
    fi
    
    echo -e "${YELLOW}WARNING: This will uninstall the Zabbix agent from a server.${NC}"
    echo -e "${CYAN}Note: This does NOT remove the host from Zabbix - use 'Remove' for that.${NC}\n"
    
    getUninstallDetails
    reviewUninstall
    confirmUninstall
}

function getUninstallDetails() {
    echo -e "${GREEN}############### Server's IP Address ###############${NC}"
    echo -e "Enter server's IP address:"
    read -r ipaddr
    validate_ip
    
    echo -e "\n${GREEN}################ Server's SSH Port ################${NC}"
    echo -e "Enter server's SSH port (default: 22):"
    read -r sshport
    sshport=${sshport:-22}
    
    serverTypeSelectForUninstall
}

function serverTypeSelectForUninstall() {
    echo -e "\n${GREEN}################### Server Type ###################${NC}\n"
    echo -e "Choose the server type:\n"
    echo -e "1. Traditional Server (root user, key already deployed)"
    echo -e "2. Traditional Server (root user, password auth)"
    echo -e "3. OpenStack Instance (non-root user, SSH key)"
    echo -e "4. Custom (specify user and auth method)"
    echo -e "\nYour choice:"
    read -r servertype
    case $servertype in
        1)
          sshuser="root"
          authmethod="key"
          # Use shared L3 key
          sshkey="/home/L3/.ssh/ultimate_support_key"
          ;;
        2)
          sshuser="root"
          authmethod="password"
          ;;
        3)
          echo -e "\n${CYAN}OpenStack default users by distro:${NC}"
          echo -e "  - Rocky Linux:    rocky"
          echo -e "  - AlmaLinux:      almalinux"
          echo -e "  - CentOS:         centos, cloud-user"
          echo -e "  - Ubuntu:         ubuntu"
          echo -e "  - Debian:         debian"
          echo -e "\nEnter SSH user:"
          read -r sshuser
          if [[ -z "$sshuser" ]]; then
              echo -e "${RED}SSH user is required for OpenStack instances.${NC}"
              serverTypeSelectForUninstall
              return
          fi
          authmethod="key"
          selectSSHKey
          ;;
        4)
          echo -e "\nEnter SSH user (default: root):"
          read -r sshuser
          sshuser=${sshuser:-root}
          selectAuthMethod
          ;;
        *)
          echo -e "${RED}Invalid choice, please try again.${NC}"
          serverTypeSelectForUninstall
          ;;
    esac
}

function reviewUninstall() {
    echo -e "\n${YELLOW}------------------- Review Uninstall -------------------${NC}"
    echo -e "${GREEN}Server IP:${NC} $ipaddr"
    echo -e "${GREEN}SSH Port:${NC} $sshport"
    echo -e "${GREEN}SSH User:${NC} $sshuser"
    echo -e "${GREEN}Auth Method:${NC} $authmethod"
    if [[ "$authmethod" == "key" ]]; then
        echo -e "${GREEN}SSH Key:${NC} $sshkey"
    fi
    echo -e "${RED}Action:${NC} Uninstall Zabbix agent from server"
    echo -e "${YELLOW}-------------------------------------------------------${NC}"
}

function confirmUninstall() {
    echo -e "\n${RED}Are you sure you want to uninstall the Zabbix agent? (yes/no)${NC}"
    echo -e "Type 'yes' to confirm:"
    read -r confirm
    if [[ $confirm == "yes" ]]; then
        runUninstallPlaybook
    elif [[ $confirm == "no" ]]; then
        echo -e "${YELLOW}Uninstall cancelled.${NC}"
        exit 0
    else
        echo -e "${RED}Invalid input, please type 'yes' or 'no'.${NC}"
        confirmUninstall
    fi
}

function runUninstallPlaybook() {
    LOGFILE="${LOGDIR}/zabbix_uninstall_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${YELLOW}Uninstalling Zabbix agent. This may take a few moments...${NC}"
    cd "$BASEDIR" || exit

    # Build the command
    local cmd="ansible-playbook playbooks/zabbix_uninstall_agent.yml"
    cmd+=" -u $sshuser"
    cmd+=" -i '$ipaddr,'"
    
    # Add authentication method
    if [[ "$authmethod" == "password" ]]; then
        cmd+=" -k"
    else
        cmd+=" --private-key '$sshkey'"
    fi
    
    # Add become if not root
    if [[ "$sshuser" != "root" ]]; then
        cmd+=" --become"
        cmd+=" --become-method sudo"
        cmd+=" --become-user root"
    fi
    
    cmd+=" -e \"ansible_port=$sshport\""
    
    # Show command being run
    echo -e "\n${CYAN}Running:${NC}"
    echo -e "$cmd\n"
    
    # Execute
    eval "$cmd" 2>&1 | tee "$LOGFILE"
    
    playbook_status=${PIPESTATUS[0]}
    
    if [[ $playbook_status -eq 0 ]]; then
        echo -e "${GREEN}Zabbix agent uninstalled successfully!${NC}"
        echo -e "${GREEN}Logs saved to:${NC} $LOGFILE"
        echo -e "\n${YELLOW}Remember to also remove the host from Zabbix using option 6 (Remove).${NC}"
    else
        echo -e "${RED}Uninstall failed. Please check the logs: ${NC}$LOGFILE"
    fi
}

# =============================================================================
# REMOVE FLOW
# =============================================================================

function removeFlow() {
    clear
    echo -e "${RED}################### Remove from Zabbix Monitoring ###################${NC}\n"
    
    # Check if removal playbook exists
    if [[ ! -f "${BASEDIR}/playbooks/zabbix_remove.yml" ]]; then
        echo -e "${RED}ERROR: Removal playbook not found at ${BASEDIR}/playbooks/zabbix_remove.yml${NC}"
        echo -e "Please ensure the playbook exists before attempting removal."
        exit 1
    fi
    
    echo -e "${YELLOW}WARNING: This will remove a host from Zabbix monitoring.${NC}\n"
    
    getRemovalDetails
    reviewRemoval
    confirmRemoval
}

function getRemovalDetails() {
    echo -e "${GREEN}Enter the Zabbix hostname to remove:${NC}"
    echo -e "${CYAN}(e.g., Mon_192.168.1.100, Ult_10.0.0.50, 100TB_203.0.113.25)${NC}"
    echo -e "\nHostname:"
    read -r zabbix_hostname_to_remove
    
    if [[ -z "$zabbix_hostname_to_remove" ]]; then
        echo -e "${RED}Hostname is required.${NC}"
        getRemovalDetails
        return
    fi
}

function reviewRemoval() {
    echo -e "\n${RED}------------------- Review Removal -------------------${NC}"
    echo -e "${GREEN}Zabbix Hostname:${NC} $zabbix_hostname_to_remove"
    echo -e "${CYAN}Action:${NC} Remove from Zabbix (API only)"
    echo -e "${RED}------------------------------------------------------${NC}"
}

function confirmRemoval() {
    echo -e "\n${RED}Are you sure you want to remove this host from Zabbix? (yes/no)${NC}"
    echo -e "${YELLOW}Type 'yes' to confirm:${NC}"
    read -r confirm
    if [[ $confirm == "yes" ]]; then
        runRemovalPlaybook
    else
        echo -e "${YELLOW}Removal cancelled.${NC}"
        exit 0
    fi
}

function runRemovalPlaybook() {
    LOGFILE="${LOGDIR}/zabbix_remove_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${YELLOW}Starting the Zabbix removal. This may take a few moments...${NC}"
    cd "$BASEDIR" || exit

    # Build the command - API only
    local cmd="ansible-playbook playbooks/zabbix_remove.yml"
    cmd+=" --vault-password-file /home/L3/.vault_pass"
    cmd+=" -e \"zabbix_agent_hostname='$zabbix_hostname_to_remove'\""
    
    # Show command being run
    echo -e "\n${CYAN}Running:${NC}"
    echo -e "$cmd\n"
    
    # Execute
    eval "$cmd" 2>&1 | tee "$LOGFILE"
    
    playbook_status=${PIPESTATUS[0]}
    
    if [[ $playbook_status -eq 0 ]]; then
        echo -e "${GREEN}Host removed from Zabbix successfully!${NC}"
        echo -e "${GREEN}Logs saved to:${NC} $LOGFILE"
    else
        echo -e "${RED}Removal failed. Please check the logs: ${NC}$LOGFILE"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

clear
echo -e "${GREEN}\t################### Zabbix Management ###################${NC}\n"

# Run pre-flight checks
preflight_check

# Start main menu
mainMenu

exit 0
