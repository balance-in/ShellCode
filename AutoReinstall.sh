#!/bin/sh

# EUID表示有效用户ID，决定用户运行时权限
# 检查有效用户ID是否为超级用户root,是否为特权进程
if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi
# 检查并安装 curl文件传输工具
if [ -f "/usr/bin/yum" ] && [ -d "/etc/yum.repos.d" ]; then
    yum install -y wget curl
elif [ -f "/usr/bin/apt-get" ] && [ -f "/usr/bin/dpkg" ]; then
    apt-get install -y wget curl	
fi

function CopyRight() {
  clear
  echo "########################################################"
  echo "#                                                      #"
  echo "#  Auto Reinstall Script                               #"
  echo "#                                                      #"
  echo "#  Author: hiCasper                                    #"
  echo "#  Blog: https://blog.hicasper.com/post/135.html       #"
  echo "#  Feedback: https://github.com/hiCasper/Shell/issues  #"
  echo "#  Last Modified: 2022-08-07                           #"
  echo "#                                                      #"
  echo "#  Supported by MoeClub                                #"
  echo "#                                                      #"
  echo "########################################################"
  echo -e "\n"
}

function isValidIp() {
  local ip=$1
  local ret=1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    ip=(${ip//\./ })
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    ret=$?
  fi
  return $ret
}
# 检查ip信息是否正确
function ipCheck() {
  isLegal=0
  for add in $MAINIP $GATEWAYIP $NETMASK; do
    isValidIp $add
    if [ $? -eq 1 ]; then
      isLegal=1
    fi
  done
  return $isLegal
}
# ip route get 1 获取到目标地址1.0.0.0时的单个路由，其中包含默认网关和源地址信息，以及用户id
# awk -F 'src ' '{print $2}以'src'分割字符串，{print $2}，打印第2个数据段. -F没有时，默认空格分割
# head -1等于 head -n 1
# 该函数用于获取ip信息
function GetIp() {
  MAINIP=$(ip route get 1 | awk -F 'src ' '{print $2}' | awk '{print $1}') #获得主机ip地址，不是公网ip
  GATEWAYIP=$(ip route | grep default | awk '{print $3}' | head -1) #获得默认网关地址
  SUBNET=$(ip -o -f inet addr show | awk '/scope global/{sub(/[^.]+\//,"0/",$4);print $4}' | head -1 | awk -F '/' '{print $2}')
  value=$(( 0xffffffff ^ ((1 << (32 - $SUBNET)) - 1) ))
  NETMASK="$(( (value >> 24) & 0xff )).$(( (value >> 16) & 0xff )).$(( (value >> 8) & 0xff )).$(( value & 0xff ))"
}

function UpdateIp() {
  read -r -p "Your IP: " MAINIP
  read -r -p "Your Gateway: " GATEWAYIP
  read -r -p "Your Netmask: " NETMASK
}
# /etc/network/interfaces网络配置文件
# -f file: file文件是否存在；-z string: 判断string字符串长度为零；-d file: file存在且是一个目录
# sed -n '/iface.*inet static/p' /etc/network/interfaces 找到interfaces文件中包含
# iface.*inet static关键字的行并打印
# find /etc/network/interfaces.d -name '*.cfg' |wc -l 找出interfaces.d目录下.cfg文件并统计个数
# 函数功能：如果有网络配置文件isAuto='0'，没有就为 '1'
function SetNetwork() {
  isAuto='0'
  if [[ -f '/etc/network/interfaces' ]];then
    [[ ! -z "$(sed -n '/iface.*inet static/p' /etc/network/interfaces)" ]] && isAuto='1'
    [[ -d /etc/network/interfaces.d ]] && {
      cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
      [[ "$cfgNum" -ne '0' ]] && { #-ne 不等于
        for netConfig in `ls -1 /etc/network/interfaces.d/*.cfg`
        do
          [[ ! -z "$(cat $netConfig | sed -n '/iface.*inet static/p')" ]] && isAuto='1'
        done
      }
    }
  fi

  if [[ -d '/etc/sysconfig/network-scripts' ]];then
    cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
    [[ "$cfgNum" -ne '0' ]] && {
      for netConfig in `ls -1 /etc/sysconfig/network-scripts/ifcfg-* | grep -v 'lo$' | grep -v ':[0-9]\{1,\}'`
      do
        [[ ! -z "$(cat $netConfig | sed -n '/BOOTPROTO.*[sS][tT][aA][tT][iI][cC]/p')" ]] && isAuto='1'
      done
    }
  fi
}

function NetMode() {
  CopyRight
  # 默认不保留当前网络配置，使用DHCP自动配置网络信息，就不保留当前网络配置
  if [ "$isAuto" == '0' ]; then
    read -r -p "Use DHCP to configure network automatically? [Y/n]:" input
    case $input in
      [yY][eE][sS]|[yY]) NETSTR='' ;;
      [nN][oO]|[nN]) isAuto='1' ;;
      *) NETSTR='' ;;
    esac
  fi
  # 保留当前网络配置信息，保留当前网络配置信息：IP地址，默认网关，子网段，网络掩码等
  if [ "$isAuto" == '1' ]; then
    GetIp
    ipCheck
    if [ $? -ne 0 ]; then # $? 最后运行的命令的结束代码（返回值）
      echo -e "Error occurred when detecting ip. Please input manually.\n"
      UpdateIp
    else
      CopyRight
      echo "IP: $MAINIP"
      echo "Gateway: $GATEWAYIP"
      echo "Netmask: $NETMASK"
      echo -e "\n"
      read -r -p "Confirm? [Y/n]:" input
      case $input in
        [yY][eE][sS]|[yY]) ;;
        [nN][oO]|[nN])
          echo -e "\n"
          UpdateIp
          ipCheck
          [[ $? -ne 0 ]] && {
            clear
            echo -e "Input error!\n"
            exit 1
          }
        ;;
        *) ;;
      esac
    fi
    NETSTR="--ip-addr ${MAINIP} --ip-gate ${GATEWAYIP} --ip-mask ${NETMASK}"
  fi
}

function RHELImageBootConf() {
  touch /tmp/bootconf.sh
  echo '#!/bin/sh'>/tmp/bootconf.sh

  staticIp='1'
  if [ "$isAuto" == '1' ]; then
    echo -e "\n"
    read -r -p "Writing static ip to system? [Y/n]: " input
    case $input in
      [yY][eE][sS]|[yY]) staticIp='0' ;;
      *) staticIp='1' ;;
    esac
  fi

  if [ "$isAuto" == '1' ] && [ "$staticIp" == '0' ]; then
    cat >>/tmp/bootconf.sh <<EOF
sed -i 's/dhcp/static/' /etc/sysconfig/network-scripts/ifcfg-eth0;
echo -e "IPADDR=$MAINIP\nNETMASK=$NETMASK\nGATEWAY=$GATEWAYIP\nDNS1=8.8.8.8\nDNS2=8.8.4.4" >> /etc/sysconfig/network-scripts/ifcfg-eth0
EOF
  fi
  cat >>/tmp/bootconf.sh <<EOF
rm -f /etc/rc.d/rc.local
cp -f /etc/rc.d/rc.local.bak /etc/rc.d/rc.local
rm -rf /bootconf.sh
shutdown -r now
EOF
  sed -i '/sbin\/reboot/i\ sync; umount \\$(list-devices partition |head -n1); mount -t ext4 \\$(list-devices partition |head -n1) \/mnt; cp -f \/mnt\/etc\/rc.d\/rc.local \/mnt\/etc\/rc.d\/rc.local.bak; chmod +x \/mnt\/etc\/rc.d\/rc.local; cp -f \/bootconf.sh \/mnt\/bootconf.sh; chmod 755 \/mnt\/bootconf.sh; echo \"\/bootconf.sh\" >> \/mnt\/etc\/rc.d\/rc.local; sync; umount \/mnt; \\' /tmp/InstallNET.sh
  sed -i '/newc/i\cp -f \/tmp\/bootconf.sh \/tmp\/boot\/bootconf.sh'  /tmp/InstallNET.sh
}

function Start() {
  CopyRight

  isCN='0'
  # 查看ip地区是否为中国
  geo=$(curl -fsSL -m 10 http://ipinfo.io/json | grep "\"country\": \"CN\"") 
  if [[ "$geo" != "" ]];then
    isCN='1'
  fi
  # 打印网络配置选项
  if [ "$isAuto" == '0' ]; then
    echo "Network Type: DHCP"
  else
    echo "IP: $MAINIP"
    echo "Gateway: $GATEWAYIP"
    echo "Netmask: $NETMASK"
  fi

  [[ "$isCN" == '1' ]] && echo "Location: Domestic"

  if [ -f "/tmp/InstallNET.sh" ]; then
    rm -f /tmp/InstallNET.sh
  fi
  curl -sSL -o /tmp/InstallNET.sh 'https://fastly.jsdelivr.net/gh/hiCasper/Shell@latest/InstallNET.sh' && chmod a+x /tmp/InstallNET.sh
  #curl -sSL -o /tmp/InstallNET.sh 'https://cdn.jsdelivr.net/gh/MoeClub/Note@latest/InstallNET.sh' && chmod a+x /tmp/InstallNET.sh

  CMIRROR=''
  CVMIRROR=''
  DMIRROR=''
  UMIRROR=''
  if [[ "$isCN" == '1' ]];then
    CMIRROR="--mirror http://mirrors.cloud.tencent.com/centos"
    CVMIRROR="--mirror http://mirrors.cloud.tencent.com/centos-vault"
    DMIRROR="--mirror http://mirrors.cloud.tencent.com/debian"
    UMIRROR="--mirror http://mirrors.cloud.tencent.com/ubuntu"
  fi

  sed -i 's/$1$4BJZaD0A$y1QykUnJ6mXprENfwpseH0/$1$7R4IuxQb$J8gcq7u9K0fNSsDNFEfr90/' /tmp/InstallNET.sh

  echo -e "\nPlease select an OS:"
  echo "  1) CentOS 7.8 (DD Image)"
  echo "  2) CentOS 7.6 (DD Image, ServerSpeeder Avaliable)"
  echo -e "  3) Rocky Linux 8.6 (\033[31mExperimental, NOT SUPPORT LSI/BusLogic disk controller\033[0m)"
  echo "  4) Debian 10"
  echo "  5) Debian 11"
  echo "  6) Ubuntu 16.04"
  echo "  7) Ubuntu 18.04"
  echo "  8) Ubuntu 20.04"
  echo "  9) Custom image"
  echo -e "\033[31m  Deprecated:\033[0m"
  echo "  10) CentOS 6"
  echo "  11) Debian 9"
  echo "  12) Ubuntu 14.04"
  echo "  0) Exit"
  echo -ne "\nYour option: "
  read N
  case $N in
    1) echo -e "\nPassword: Pwd@CentOS\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh $NETSTR -dd 'https://api.moetools.net/get/centos-78-image' $DMIRROR ;;
    2) echo -e "\nPassword: Pwd@CentOS\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh $NETSTR -dd 'https://api.moetools.net/get/centos-76-image' $DMIRROR ;;
    3) echo -e "\nPassword: Pwd@Linux\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh $NETSTR -dd 'https://api.moetools.net/get/rocky-8-image' $DMIRROR ;;
    4) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh -d 10 -v 64 -a $NETSTR $DMIRROR ;;
    5) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh -d 11 -v 64 -a $NETSTR $DMIRROR ;;
    6) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh -u 16.04 -v 64 -a $NETSTR $UMIRROR ;;
    7) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh -u 18.04 -v 64 -a $NETSTR $UMIRROR ;;
    8) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh -u 20.04 -v 64 -a $NETSTR $UMIRROR ;;
    9)
      echo -e "\n"
      read -r -p "Custom image URL: " imgURL
      echo -e "\n"
      read -r -p "Are you sure start reinstall? [y/N]: " input
      case $input in
        [yY][eE][sS]|[yY]) bash /tmp/InstallNET.sh $NETSTR -dd $imgURL $DMIRROR ;;
        *) clear; echo "Canceled by user!"; exit 1;;
      esac
      ;;
    10) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh -c 6.10 -v 64 -a $NETSTR $CMIRROR ;;
    11) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh -d 9 -v 64 -a $NETSTR $DMIRROR ;;
    12) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh -u 14.04 -v 64 -a $NETSTR $UMIRROR ;;
    0) exit 0;;
    *) echo "Wrong input!"; exit 1;;
  esac
}

SetNetwork
NetMode
Start
