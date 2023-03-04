#!/bin/bash

echo " ___    ____   _____ ____   __ __  _____ ______    ___  ____  "
echo "|   \  |    \ / ___/|    \ |  |  |/ ___/|      |  /  _]|    \ "
echo "|    \ |  _  (   \_ |  o  )|  |  (   \_ |      | /  [_ |  D  )"
echo "|  D  ||  |  |\__  ||     ||  |  |\__  ||_|  |_||    _]|    / "
echo "|     ||  |  |/  \ ||  O  ||  :  |/  \ |  |  |  |   [_ |    \ "
echo "|     ||  |  |\    ||     ||     |\    |  |  |  |     ||  .  \\"
echo "|_____||__|__| \___||_____| \__,_| \___|  |__|  |_____||__|\_|"
echo "                                        @AchocolatechipPancake"
echo "                                        @Cosm1c               "
echo ""

unset -v domainsfile
unset -v scopefile

while getopts d:s: opt; do
        case $opt in
                d) domainsfile=$OPTARG ;;
                s) scopefile=$OPTARG ;;
                *)
                        echo 'Error in command line parsing' >&2
                        echo ''
                        echo "Usage: $(basename $0) [-d <DomainFileLocation>] [-s <ScopeFileLocation>]"
                        exit 1
        esac
done
shift "$(( OPTIND - 1 ))"

if [ -z "$domainsfile" ] || [ -z "$scopefile" ]; then
        echo 'Missing -d or -s' >&2
        echo ''
        echo "Usage: $(basename $0) [-d <DomainFileLocation>] [-s <ScopeFileLocation>]"
        exit 1
fi

echo "Checking if dependancies are installed"
check=$(which amass)
if [[ -n "$check" ]]; then
  echo '  -amass is installed.'
else
  echo '  -Installing amass'
  sudo apt install amass -y > /dev/null 2>&1
fi

check=$(which seclists)
if [[ -n "$check" ]]; then
  echo '  -Seclists is installed.'
else
  echo '  -Installing Seclists'
  sudo apt install seclists -y > /dev/null 2>&1
fi

check=$(which assetfinder)
if [[ -n "$check" ]]; then
  echo '  -AssetFinder is installed.'
else
  echo '  -Installing AssetFinder'
  sudo apt install assetfinder -y > /dev/null 2>&1
fi

check=$(which massdns)
if [[ -n "$check" ]]; then
  echo '  -massdns is installed.'
else
  echo '  -Installing massdns'
  sudo apt install massdns -y > /dev/null 2>&1
fi

check=$(which amass)
if [[ -n "$check" ]]; then
  echo '  -Nuclei is installed.'
else
  echo '  -Installing Nuclei'
  sudo apt install nuclei -y > /dev/null 2>&1
fi

sudo apt install httpx-toolkit -y > /dev/null 2>&1


if [ ! -f "$domainsfile" ]; then
    echo "$domainsfile does not exist. Please provide a valid file."
    exit
fi

folder="$(date +"%d-%m-%Y")"
if [ -d "$folder" ];
then
    echo "$folder directory exists. Creating another."
    mv $folder $folder"-previous"
    mkdir $folder; cd $folder
    
else
	mkdir $folder; cd $folder
fi
wget "https://public-dns.info/nameserver/us.txt" -O resolve.txt >> /dev/null 2>&1
domainsfilelocation="../$domainsfile"
cat $domainsfilelocation | while read line; do assetfinder $line -subs-only >> known_subdomains.txt; done;
echo "AssetFinder has finished."
massdns -r resolve.txt -o S ../$domainsfile -q | grep -e ' A ' | sort | uniq > massdns.out;
echo "MassDNS has finished."
rm resolve.txt
echo "Amass is running, this might take a while."
echo ""
amass enum -active -df $domainsfilelocation -nf known_subdomains.txt -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt -src -ip -max-depth 3 -brute -dns-qps 200 -o amass_all_domains
echo ""
echo "Amass has finished."
mkdir lists
while read -r IP;do grep -P "(\h|,)$IP(,|$)" amass_all_domains;done < ../$scopefile >> in-scope-results.txt
cat in-scope-results.txt | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' >> lists/results-ipv4.txt
awk -F ']' '{ print $2 }' in-scope-results.txt | sed -r 's/(\b[0-9]{1,3}\.){3}[0-9]{1,3}\b'/" "/ | sed 's/^[ \t]*//' | awk '{print $1}' >> lists/results-hostnames.txt
mv known_subdomains.txt lists/known_subdomains.txt
echo "Amass IPs/Hostnames can be found in $folder/lists"
echo ""
echo "httpx-toolkit is running."
httpx-toolkit -follow-redirects -l lists/results-ipv4.txt -mc 200,201,301,302 -ports 22,443,8000,8006,8081,8085,8189,8199,25055 >> httpx.out
echo "httpx-toolkitcd ../ has finished."
echo ""
echo "Nuclei is running."
nuclei -l httpx.out timeout 15 -project $PWD >> nuclei.out
echo "Nuclei has finished."
echo "All OSINT Scans have been completed."
