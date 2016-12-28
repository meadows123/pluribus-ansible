#!/usr/bin/env bash

function error() {
  echo -e "\e[0;33mERROR: The ZTP script failed while running the command $BASH_COMMAND at line $BASH_LINENO.\e[0m" >&2
  exit 1
}
trap error ERR

RED='\033[0;31m'
NC='\033[0m'

default_conf_file="# If you want to install ansible using GIT then provide GIT keyword in ansible_install_approach variable.Dont use quotes for value.(Default Value - OS-INSTALLER)
ansible_install_approach=OS-INSTALLER
# On what interfaces should the DHCP server (dhcpd) serve DHCP requests
dhcp_network_interface=eno16777984
# Netmask of DHCP server host
dhcp_subnet-mask=255.255.0.0
# Broadcast address of DHCP server host
dhcp_broadcast-address=10.9.255.255
# Routers for DHCP server host
dhcp_routers=10.9.9.1
dhcp_dns=10.9.10.1, 8.8.8.8
dhcp_domain-name=pluribusnetworks.com
dhcp_subnet_address=10.9.0.0
dhcp_range=10.9.1.1 10.9.1.100"

default_csv_file="02:42:b4:c9:6d:1e,10.9.1.1,pikachu,spine
8c:89:a5:f4:28:2f,10.9.1.2,lapras,leaf
8c:89:a5:f4:23:1f,10.9.1.3,,spine
8c:89:a5:f3:28:2e,10.9.1.4,gyarados,,"

default_csv_file_onie="02:42:b4:c9:6d:1e,10.9.1.1,pikachu,spine,671232X1646008
8c:89:a5:f4:28:2f,10.9.1.2,lapras,leaf,671232X1645002
8c:89:a5:f4:23:1f,10.9.1.3,,spine,671232X1646009
8c:89:a5:f3:28:2e,10.9.1.4,gyarados,,671232X1646010"

help="
${RED}NAME${NC}
     ztp — Script to configure DHCP, ONIE etc
                  to check availability of provided hosts

${RED}SYNOPSIS${NC}
     bash ztp.sh [-h/-help] [-dhcp] [-onie] [-conf file.conf] [-csv file.csv] [-reconfigure_dhcp] 
                 [-skip_ansible] [-online_onie] [-offline_onie] [-online_license] [-offline_license] [-checkallsystemsgo]

${RED}OPTIONS${NC}

     -h or -help:        Display brief usage message.
   
     -dhcp:              This field will install dhcpserver and ansible. 

     -onie:              This field configures your system to act as a ONIE Server.

     -conf:              Reads conf file as input. This file contains network information required by switches. e.g netmask, domain-name, dns etc

     -csv:               Reads csv file as input. This section contains MAC, IP list, Hostname,TAG field and Inband ip entries which is required to create mac-ip mappings.
                         MAC and IP address fields are compulsory. Please provide comma for optional fields if it does not have any value.
                         Please check below CSV file example.
  
     -reconfigure_dhcp:  Script will create new dhcpd.conf file from the provided conf file. Otherwise it will append contents to present file.

     -skip_ansible:      This field will skip installations of ansible, python and pip modules.

     -online:            This field will download ONIE image and activation keys automatically.

     -offline:           In this field user needs to download ONIE image and activation keys manually.

     -online_onie:       This field will download ONIE image automatically. User just need to provide versio of image in conf file.
 
     -offline_onie:      In this field user needs to download ONIE image manually and keep it in web server directory. i.e /var/www/html/images
 
     -online_license:    This field will download activation keys automatically.

     -offline_license:   In this field user needs to download activation keys manually.
 
     -checkallsystemsgo: This field will check availability of all the hosts mentioned in the CSV file.

${RED}EXAMPLES: ${NC}
     bash ztp.sh -dhcp -conf file.conf
     bash ztp.sh -dhcp -conf file.conf -csv file.csv
     bash ztp.sh -dhcp -conf file.conf -csv file.csv -reconfigure_dhcp
     bash ztp.sh -dhcp -conf file.conf -csv file.csv -reconfigure_dhcp -skip_ansible
     bash ztp.sh -onie -conf file.conf -csv file.csv -online -skip_ansible
     bash ztp.sh -onie -conf file.conf -csv file.csv -offline -skip_ansible
     bash ztp.sh -onie -conf file.conf -csv file.csv -online -reconfigure_dhcp
     bash ztp.sh -onie -conf file.conf -csv file.csv -offline -reconfigure-dhcp
     bash ztp.sh -onie -conf file.conf -csv file.csv -offline_onie online_license
     bash ztp.sh -onie -conf file.conf -csv file.csv -offline_license online_oniei
     bash ztp.sh -checkallsystemsgo

${RED}=> For DHCP : Contents of file.conf:${NC}
$default_conf_file

${RED}=> For DHCP : Contents of file.csv:${NC}
$default_csv_file

${RED}=> For ONIE : Contents of file.conf ${NC}
$default_conf_file
default-url=http://dhcpserverip/images/onie-installer
username=ansible  #In case of online version
password=test123  #In case of online version
onie_image_version=2.5.1-10309 #In case of online version

${RED}=> For ONIE: Contents of file.csv:${NC}
$default_csv_file_onie

"

#Checks operating system type
if [ -f "/etc/redhat-release" ]; then
OS="Centos"
elif [ -f "/etc/lsb-release" ]; then
OS="Ubuntu"
fi

csv_file=""
processCsv=0
device_id=()
script_dir=`pwd`

##This function validates ipaddress and mac address from CSV file. 
validate_csv()
{
  # CSV File validation
  cd $script_dir
  params=$@
  processCsv=0
  if [[ "$params" == *"-csv"* ]]; then
    csv_file=`echo "${params#*-csv[$IFS]}" | awk '{ print $1 }'`

    if [ ! -e $csv_file  ]; then
    echo -e "\nCSV file is not present or not in readable format\n"
      exit 0
    else
      comma_count=2
    
      for line in `cat $csv_file` ;
      do
        commas=`echo $line | awk -F "," '{print NF-1}'`
        if [ "$commas" -le "$comma_count" ];then
          printf "\n\nPlease provide correct arguments separated by commas. Use ,, inplace of optional value. Check sample csv file from Help\n\n"
          exit 0
        fi
      done
 
      #Checking whether user has provided correct mac and ip addresses
      for line in `cat $csv_file` ;
      do
        mac_address=`echo $line | cut -d "," -f1`
        ip_address=`echo $line | cut -d "," -f2`

        if [[ "$mac_address" =~ ^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$ ]]; then
          if [[ $ip_address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            processCsv=1
          else
            printf "${RED}Check your CSV file. Please provide ip address in correct format${NC}\n"
            exit 0
          fi
        else
          printf "${RED}Check your CSV file. Please provide mac address in correct format${NC}\n"
          exit 0
        fi
      done
    fi
  fi
}

##This function installs Ansible using GIT 
install_ansible_using_git()
{
  ansible_directory="/etc/ansible"
  if [ -d "$ansible_directory" ]; then
    sudo rm -r $ansible_directory
  fi
  cd /etc/
  sudo git clone git://github.com/ansible/ansible.git --recursive
  cd ./ansible
  sudo -s source ./hacking/env-setup
  sudo easy_install pip
}


##This function configures dhcp server. 
dhcpserver()
{
  params=$@
  conf_file=`echo "${params#*-conf[$IFS]}" | awk '{ print $1 }'`

  if [ ! -e "$conf_file"  ]; then
    echo -e "\nConfiguration file is not present or not in readable format.Try providing full path of file.\n"
    exit 0
  else
    interface=`cat "$conf_file" | grep 'dhcp_network_interface' | cut -d = -f2`
    subnet_mask=`cat "$conf_file" | grep 'dhcp_subnet-mask' | cut -d = -f2`
    broadcast_address=`cat "$conf_file" | grep 'dhcp_broadcast-address' | cut -d = -f2`
    routers=`cat "$conf_file" | grep 'dhcp_routers' | cut -d = -f2`
    dns=`cat "$conf_file" | grep 'dhcp_dns' | cut -d = -f2`
    domain_name=`cat "$conf_file" | grep 'dhcp_domain-name' | cut -d = -f2`
    subnet=`cat "$conf_file" | grep 'dhcp_subnet_address' | cut -d = -f2`
    range=`cat "$conf_file" | grep 'dhcp_range' | cut -d = -f2`
  fi

  if [[ "$params" == *"-csv"* ]]; then
    validate_csv "$params"
  fi

  ansible_install_approach=`cat $conf_file | grep 'ansible_install_approach=' | cut -d = -f2`

  if [ $OS == "Ubuntu" ]; then
      sudo apt-get -qq update -y
      sudo apt-get -qq install isc-dhcp-server -y
      sudo sed -i '/INTERFACES=/c INTERFACES="'$interface'"' /etc/default/isc-dhcp-server
      dhcp_restart_command='sudo service isc-dhcp-server restart'
      if [ "$ansible_install_approach" == "GIT" ]; then
        #Installing latest Ansible - Using git
        sudo apt-get -y install git
        install_ansible_using_git
      elif [ "$ansible_install_approach" == "OS-INSTALLER" ]; then
        #Installing latest Ansible - Using apt-get
        sudo apt-get -qq install software-properties-common
        sudo apt-add-repository -y ppa:ansible/ansible
        sudo apt-get -qq update
        sudo apt-get -qq -y install ansible
        sudo apt-get -qq -y install python
        sudo apt-get -qq -y install python-pip
      fi
      sudo pip install paramiko PyYAML Jinja2 httplib2 six > /dev/null
  elif [ $OS == "Centos" ]; then
      sudo yum -y update
      sudo yum -y install dhcp
      count=`cat /etc/sysconfig/dhcpd | grep 'DHCPDARGS=' | wc -l`
      if [ $count == "1" ]; then
        sed -i "/DHCPDARGS=/c DHCPDARGS=$interface" /etc/sysconfig/dhcpd
      else
        echo "DHCPDARGS=$interface" >> /etc/sysconfig/dhcpd
      fi
      dhcp_restart_command='sudo systemctl restart dhcpd'
      if [ "$ansible_install_approach" == "GIT" ]; then
        sudo yum -y install git
        install_ansible_using_git
      elif [ "$ansible_install_approach" == "OS-INSTALLER" ]; then
        sudo yum -y -q install epel-release
        sudo yum -y -q update
        sudo yum -y -q install ansible
        sudo yum -y -q install python
        sudo yum -y -q install python-pip
      fi
  fi

  ymlfiles=(bgpsetup.yml bgpteardown.yml cli_vault.yml l2setup.yml l2teardown.yml main.yml pn_ebgp.yml pn_fabric.yml pn_fabric_l3_ebgp.yml pn_l2.yml pn_l2_ztp.yml pn_l3.yml pn_l3_ebgp.yml pn_l3_ztp.yml pn_vrrp.yml)
  sudo mkdir -p /etc/ansible
  cd /etc/ansible
  for i in ${ymlfiles[@]}; do
    sudo wget --quiet https://github.com/amitsi/pluribus-ansible/blob/master/ansible/$i
  done

check_conf_exists=`cat /etc/dhcp/dhcpd.conf | grep '#DHCP SERVER CONF FILE' | wc -l`

  if [ $check_conf_exists == 0 ] || [[ "$params" == *"-reconfigure-dhcp"* ]]; then
sudo sh -c "echo '#DHCP SERVER CONF FILE
# option definitions common to all supported networks...
default-lease-time 600;
max-lease-time 7200;
# If this DHCP server is the official DHCP server for the local
# network, the authoritative directive should be uncommented.
authoritative;
# Use this to send dhcp log messages to a different log file (you also
# have to hack syslog.conf to complete the redirection).
log-facility local7;

subnet "$subnet" netmask "$subnet_mask" {  #network
  range $range; # Range
  option domain-name-servers "$dns"; #Pri DNS , Sec DNS
  option domain-name \"$domain_name\"; #Domain name
  option routers "$routers"; #Gateway
  option broadcast-address "$broadcast_address"; #Broadcast
  default-lease-time 600;
  max-lease-time 7200;
}
' > /etc/dhcp/dhcpd.conf"
  fi

  if [ $processCsv == 1 ]; then

    #Appending dhcpd.conf file with mac-ipaddress entries
    spine=()
    leaf=()

    for line in `cat $csv_file` ;
    do
      arr=()
      IFS=',' read -a arr <<< "$line"
      mac=${arr[0]}
      ip=${arr[1]}
      hostname=${arr[2]}
      tag=${arr[3]}
      device_id+=(${arr[4]})
  
      check_block_entry_exists=`cat /etc/dhcp/dhcpd.conf | grep "$mac" | wc -l`

      if [ -z $hostname ]; then
      host_block="host $ip {
  hardware ethernet $mac;
  fixed-address $ip;
"
      else
      host_block="host $hostname {
  hardware ethernet $mac;
  fixed-address $ip;
  option host-name \"$hostname\";
"
     fi

      if [[ "$params" == *"-onie"* ]]; then
        url=`cat $conf_file | grep 'default-url=' | cut -d = -f2`
        host_block="$host_block  option default-url=\"$url\";"
      fi
  host_block="$host_block
}"

      if [ $check_block_entry_exists == 0 ]; then
        sudo sh -c "echo '$host_block' >> /etc/dhcp/dhcpd.conf"
      fi

      if ! [ -z "$tag" ]; then
        if [ "$tag" == "spine"  ]; then
          spine+=($ip)
        else
          leaf+=($ip)
        fi
      fi
    done


    echo "[spine]" > /etc/ansible/hosts
    for spineswitch in "${spine[@]}"
    do
      echo "$spineswitch" >> /etc/ansible/hosts
    done

    echo -e "\n" >> /etc/ansible/hosts

    echo "[leaf]" >> /etc/ansible/hosts
    for leafswitch in "${leaf[@]}"
    do
     echo "$leafswitch" >> /etc/ansible/hosts
    done

  fi #end of processCsv

  #Restart dhcp server
  eval $dhcp_restart_command
}

##This function configures dhcp server and onie system on provided box.
onie()
{
  declare params=$@
  conf_file=`echo "${params#*-conf[$IFS]}" | awk '{ print $1 }'`
  validate_csv "$params"

  #install apache2 server
  printf "Updating respositories\n"
  sudo apt-get -y -qq update
  printf "Installing apache2\n"
  sudo apt-get -y -qq install apache2
  printf "Installed apache2 successfully\n"

  dhcpserver "$params"
  cd $script_dir
  username=""
  password=""
  `pwd`
  cookie_file_name="/tmp/cookie"
  if [[ "$params" == *"-online"* ]]; then
    printf "\n\nconfiguring JQ json parser\n\n"
    if ! [ -f ./jq ]; then
      sudo wget --quiet http://stedolan.github.io/jq/download/linux64/jq
    fi
    `pwd`
    sudo chmod +x ./jq
    sudo cp jq /usr/bin
    username=`cat $conf_file | grep 'username=' | cut -d = -f2`
    password=`cat $conf_file | grep 'password=' | cut -d = -f2`
  fi

  if [[ "$params" == *"-online" ]];then
    mkdir -p /var/www/html/images 
    version=`cat $conf_file | grep 'onie_image_version=' | cut -d = -f2`
    login_json=`curl -X POST https://cloud-web.pluribusnetworks.com/api/login -d login_email=$username\&login_password=$password -k -c $cookie_file_name`
    login_result=`echo $login_json | jq '.success'`

    if ! [ "$login_result" == true ]; then
      printf "\n\nLogin failed: cloud-web.pluribusnetworks.com. Please provide correct credentials in conf file\n\n"
      exit 0
    fi

    order_details_json=`curl -X GET https://cloud-web.pluribusnetworks.com/api/orderDetails -b $cookie_file_name -k`
    order_detail_id=`echo $order_details_json | jq '.order_details[1].id'`
    for id in "${device_id[@]}"
    do
      printf "\n\n Activating key\n\n"
      activation_json=`curl -X POST https://cloud-web.pluribusnetworks.com/api/orderActivations -d order_detail_id=$order_detail_id\&device_ids=$id\&csrfmiddlewaretoken=$csrftoken -b $cookie_file_name -k`
      activation_result=`echo $activation_json | jq '.success'`
      if ! [ "$activation_result" == true ]; then
        printf "\n\nUnable to activate key for Device: $id\n\n"
      fi
    done
    curl -X GET https://cloud-web.pluribusnetworks.com/api/offline_bundle/$order_detail_id -b $cookie_file_name -k > /etc/pluribuslicense/onvl-activation-keys
    cd /var/www/html/images
    printf "\n\nDownloading image in /var/www/html/images. Make sure you have provided default-url parameter value as http://ip_of_dhcp_server/images/onie-installer. in conf file\n\n"
    curl -o onie-installer -H 'Accept-Encoding: gzip, deflate, br' -X GET https://cloud-web.pluribusnetworks.com/api/download_image1/onie-installer-$version\?version\=$version -b $cookie_file_name -k
    printf "\n\nDownloaded image in /var/www/html/images.\n\n"

  elif [[ "$params" == *"-offline" ]]; then
    echo "Configuring ONIE: Offline"

  elif [[ "$params" == *"-online_onie" ]] && [[ "$params" == *"-offline_license" ]] ; then 
    mkdir -p /var/www/html/images 
    version=`cat $conf_file | grep 'onie_image_version=' | cut -d = -f2`
    login_json=`curl -X POST https://cloud-web.pluribusnetworks.com/api/login -d login_email=$username\&login_password=$password -k -c $cookie_file_name`
    login_result=`echo $login_json | jq '.success'`
    if ! [ "$login_result" == true ]; then
      printf "\n\nLogin failed: cloud-web.pluribusnetworks.com. Please provide correct credentials in conf file\n\n"
      exit 0
    fi
    cd /var/www/html/images
    printf "\n\nDownloading image in /var/www/html/images. Make sure you have provided default-url parameter value as http://ip_of_dhcp_server/images/onie-installer. in conf file\n\n"
    curl -o onie-installer -H 'Accept-Encoding: gzip, deflate, br' -X GET https://cloud-web.pluribusnetworks.com/api/download_image1/onie-installer-$version\?version\=$version -b $cookie_file_name -k
    printf "\n\nDownloaded image in /var/www/html/images.\n\n"

  elif [[ "$params" == *"-offline_onie" ]] && [[ "$params" == *"-online_license" ]]; then
    login_json=`curl -X POST https://cloud-web.pluribusnetworks.com/api/login -d login_email=$username\&login_password=$password -k -c $cookie_file_name`
    login_result=`echo $login_json | jq '.success'`
    if ! [ "$login_result" == true ]; then
      printf "\n\nLogin failed: cloud-web.pluribusnetworks.com. Please provide correct credentials in conf file\n\n"
      exit 0
    fi
    order_details_json=`curl -X GET https://cloud-web.pluribusnetworks.com/api/orderDetails -b $cookie_file_name -k`
    order_detail_id=`echo $order_details_json | jq '.order_details[1].id'`
    for id in "${device_id[@]}"
    do
      printf "\n\n Activating key\n\n"
      activation_json=`curl -X POST https://cloud-web.pluribusnetworks.com/api/orderActivations -d order_detail_id=$order_detail_id\&device_ids=$id\&csrfmiddlewaretoken=$csrftoken -b $cookie_file_name -k`
      activation_result=`echo $activation_json | jq '.success'`
      if ! [ "$activation_result" == true ]; then
        printf "\n\nUnable to activate key for Device: $id\n\n"
      fi
    done
    curl -X GET https://cloud-web.pluribusnetworks.com/api/offline_bundle/$order_detail_id -b $cookie_file_name -k > /etc/pluribuslicense/onvl-activation-keys
  else
    printf "\nPlease provide one of these parameters \n1. -online \n2. -offline \n3. -offline_onie -online_license \n4. -online_onie -offline_license\n"
  fi

  ##Reload apache service
  sudo service apache2 reload

}

checkallsystemsgo()
{
   params=$@
   if ! [[ "$params" == *"-csv"* ]]; then
      printf "\nScript requires .csv file as argument to read host ips. Please provide csv file as an argument : ${RED}bash ${0##*/} -checkallsystemsgo -csv filename.csv${NC}\n\n"
      exit 0
   else
     csv_file=`echo "${params#*-csv[$IFS]}" | awk '{ print $1 }'`
     if [ ! -e $csv_file  ]; then
       echo -e "\nCSV file is not present or not in readable format\n"
       exit 0
     else
       if [[ "$params" == *"-csv"* ]]; then
         validate_csv "$params"
       fi

       if [ $processCsv == 1 ]; then
         for line in `cat $csv_file` ;
         do
           arr=()
           IFS=',' read -a arr <<< "$line"
           count=`ping -c 1 ${arr[1]} | grep '1 received' | wc -l`
           if [ "$count" == 1 ];then
             printf "\n\nHost is UP and running with IP: ${arr[1]}\n\n"
           else
             printf "\n\nHost is down or IP is not yet assigned: ${arr[1]}\n\n"  
           fi
         done 
       fi
     fi
   fi
}


##This is the main function which parses the arguments and depending on that it calls different functions.
main()
{
  declare params="$@"
  if [[ "$params" = *"-h"* ]] || [[ "$params" = *"-help"* ]] || [[ "$params" = *"--h"* ]] || [[ "$params" = *"--help"* ]] || [[ "$params" == 0 ]] ; then
    printf "\n\e[0;31m[ZTP] \e[0m"
    printf "$help"
    exit 0
  fi

  #####DHCP#######
  if  [[ "$params" == *"-dhcp"* ]]; then
    choice="n"
    choice1="n"
    if ! [[ "$params" == *"-conf"* ]]; then
      printf "\nScript requires .conf file as argument. Please provide configuration file as an argument : ${RED}bash ${0##*/} -dhcp -conf filename.conf${NC}\n\n"
      printf "Shall I generate sample conf file in /tmp/file.conf. ${RED}(y/n):${NC}"
      read choice
      if [ $choice == "y" ]; then
        echo "$default_conf_file" > /tmp/file.conf
        printf "\n#####Sample Conf file is created in /tmp/file.conf with following contents######\n"
        printf "\n${RED}$default_conf_file${NC}\n\n"
      fi
      exit 0
    fi
    dhcpserver "$params"
    exit 0

  ########ONIE##############
  elif [[ "$params" == *"-onie"* ]]; then
    if ! [[ "$params" == *"-conf"* ]] && ! [[ "$params" == *"-csv"* ]]; then
      printf "\nScript requires conf and csv file as an argument. These files will be passed as an argument to dhcpserver function. \nExample: ${RED}bash ${0##*/} -onie -conf filename.conf -csv filename.csv ${NC}\n\n"
      printf "Shall I generate sample conf and csv file in /tmp/file.conf and /tmp/file.csv respectively. ${RED}(y/n):${NC}"
      read choice1
      if [ $choice1 == "y" ]; then
        default_conf_file="$default_conf_file
default-url=http://ip_of_dhcp_server/images/onie-installer
username=ansible #In case of online version
password=test123 #In case of online version
onie_image_version=2.5.1-10309 #In case of online version"

        echo "$default_conf_file" > /tmp/file.conf
        printf "\n#####Sample Conf file is created in /tmp/file.conf with following contents######\n"
        printf "\n${RED}$default_conf_file${NC}\n\n"
        printf "\n#####Sample CSV file is created in /tmp/file.csv with following contents######\n"
        printf "\n${RED}$default_csv_file${NC}\n\n"
      fi
      exit 0
    fi

    conf_file=`echo "${params#*-conf[$IFS]}" | awk '{ print $1 }'`
    if [[ `cat $conf_file | grep 'default-url='` ]]; then
      url=`cat $conf_file | grep 'default-url=' | cut -d = -f2`
    else
      printf "\nScript requires default-url parameter for http server purpose. Please provide default-url parameter in conf file. \nExample: ${RED}default-url=http://ip_of_dhcp_server/images/onie-installer${NC}\n\n"
      exit 0
    fi

    if ! [[ "$params" == *"-online" ]] && ! [[ "$params" == *"-offline" ]] && ! [[ "$params" == *"-offline_onie -online_license" ]] && ! [[ "$params" == *"-online_onie -offline_license" ]]; then
      printf "\nPlease provide one of these parameters \n1. -online \n2. -offline \n3. -offline_onie -online_license \n4. -online_onie -offline_license\n"
      exit 0
    fi

    if [[ "$params" == *"-online"* ]]; then
      if ! [ `cat $conf_file | grep 'username='` ]; then
        printf "\nPlease provide username value in conf file.\n\n"
        exit 0
      fi

      if ! [[ `cat $conf_file | grep 'password='` ]]; then
        printf "\nPlease provide password value in conf file.\n\n"
        exit 0
      fi

      if ! [[ `cat $conf_file | grep 'onie_image_version='` ]]; then
        printf "\nPlease provide image version value in conf file.\n\n"
        exit 0
      fi
    fi
    onie "$params"
    exit 0
  elif [[ "$params" == *"-checkallsystemsgo"* ]]; then
    checkallsystemsgo "$params"
  else
    printf "\nCurrently ZTP Script provides 3 functions. i.e DHCP, ONIE and check systems availability. So please provide any of the following options as parameter\n"
    printf "\n1. -dhcp"
    printf "\n2. -onie\n"
    printf "\n3. -checkallsystemsgo"
    printf "\nor run command bash ztp.sh -help\n\n"
  fi

}

main "$@"

