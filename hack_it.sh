
resetColor="\e[0m"
redColor="\e[31m"
greenColor="\e[32m"
yellowColor="\e[33m"


echo -e "${greenColor}
         _____
 |     |   |   ${redColor}Hack It ${greenColor}
 |-----|   |    
 |     |   |> > ${redColor}A Tool To Scan Apks for Firestore Vulnerability${greenColor}
    
"

checkTool() {
    if ! dpkg -l "$1" >/dev/null 2>&1; then
        echo -e "${yellowColor}[!] Installing $1...${resetColor}\n"
        apt-get update -y >/dev/null 2>&1
        apt-get install "$1" -y >/dev/null 2>&1
    fi
}

quit() {
    rm -rf "$filename"
    exit
}

checkCollections() {
    echo
    if [[ "$1" ]]; then
        token="$1"
        if echo "$1" | grep -q ":"; then
            if ! apiKey=$(grep -i "google_api_key" "$filename/res/values/strings.xml"); then
                echo -e "${redColor}[-] google_api_key not found in res/values/strings.xml file.${resetColor}"
                quit
            else
                echo -e "${greenColor}[+] google_api_key found in res/values/strings.xml file:${resetColor}"
                apiKey=$(echo "$apiKey" | sed -n 's:.*<string name="google_api_key">\(.*\)</string>.*:\1:pI')
                echo -e "$apiKey\n"
            fi

            email=$(echo "$1" | cut -d: -f1)
            password=$(echo "$1" | cut -d: -f2)

            token=$(curl -s -X POST -H "Content-Type: application/json" -d "{
'email':'$email',
'password':'$password',
'returnSecureToken':true
}" "https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=$apiKey" | jq -r '.idToken')

            if [[ "$token" == "null" ]]; then
                echo -e "${redColor}[-] Failed to get an authentication token.${resetColor}"
                quit
            else
                echo -e "${greenColor}[+] It was possible to obtain an authentication token:${resetColor}\n$token\n"
            fi

        fi
        declare -a authHeader=('-H' "Authorization: Bearer $token")
    fi
    for c in "${collections[@]}"; do
        outputReadable=$(curl "${authHeader[@]}" -s "https://firestore.googleapis.com/v1beta1/projects/$projectID/databases/(default)/documents/$c")
        if echo "$outputReadable" | grep -q '"error":'; then
            echo -e "${redColor}[-] The collection $c is not readable.${resetColor}"
        else
            echo -e "${greenColor}[+] The collection $c is readable:${resetColor}\n$outputReadable"
        fi
        outputWritable=$(curl "${authHeader[@]}" -X POST -s "https://firestore.googleapis.com/v1/projects/$projectID/databases/(default)/documents/$c" -H "Content-Type: application/json" -d '{
"fields": {
"fspPoC": {
"stringValue": "writable"
},
}
}')
        if echo "$outputWritable" | grep -q '"error":'; then
            echo -e "${redColor}[-] The collection $c is not writable.${resetColor}"
        else
            echo -e "${greenColor}[+] The collection $c is writable:${resetColor}\n$outputWritable"
            writtenCollectionID=$(echo "$outputWritable" | jq -r '.name' | rev | cut -d'/' -f 1 | rev)
            sleep 2
            curl "${authHeader[@]}" -X DELETE -s "https://firestore.googleapis.com/v1beta1/projects/$projectID/databases/(default)/documents/$c/$writtenCollectionID"
        fi
    echo
    done
}

checkTool "apktool"
checkTool "jq"

if [[ -f "$1" ]]; then
    filename=$(basename -- "$1")
    extension="${filename##*.}"
    filename="fsp-${filename%.*}"

    if [[ "$extension" == "apk" ]]; then
        echo -e "${yellowColor}[!] The specified APK is $1.${resetColor}\n"

        if apktool d "$1" -o "$filename" >/dev/null 2>&1; then
            echo -e "${greenColor}[+] Successful decompilation with apktool.${resetColor}\n"
        else
            echo -e "${redColor}[-] Decompilation failed with apktool.${resetColor}"
            quit
        fi

        if ! grep -qi "firebase" "$filename/AndroidManifest.xml"; then
            echo -e "${redColor}[-] Firebase not found in the AndroidManifest.xml${resetColor}"
            quit
        else
            echo -e "${greenColor}[+] Firebase found in the AndroidManifest.xml${resetColor}\n"
            if ! projectID=$(grep -i "project_id" "$filename/res/values/strings.xml"); then
                echo -e "${redColor}[-] project_id not found in res/values/strings.xml file.${resetColor}"
                quit
            else
                echo -e "${greenColor}[+] project_id found in res/values/strings.xml file:${resetColor}"
                projectID=$(echo "$projectID" | sed -n 's:.*<string name="project_id">\(.*\)</string>.*:\1:pI')
                echo -e "$projectID\n"
                matchString="lcom/google/firebase/firestore/FirebaseFirestore"
                for c in $(grep -hA 2 "$matchString" -irw "$filename"/smali* 2>/dev/null | grep -iv "$matchString" | grep const-string | sed 's/[^"]*"\([^"]*\)".*/\1/' | sort -u | sed 's/Provided data must not be null.//g'); do
                    collections+=("$c")
                done

                if [ "${#collections[@]}" -eq 0 ]; then
                    echo -e "${redColor}[-] No collections found in .smali files.${resetColor}"
                    quit
                else
                    echo -e "${greenColor}[+] ${#collections[@]} Collection(s) found in .smali files.${resetColor}"
                    for c in "${collections[@]}"; do
                         echo "$c"
                    done; echo

                    echo -e "${yellowColor}[!] IMPORTANT: Consulting collections can have an economic impact on the objective."
                    echo -e "    Firestore has a daily expense depending on the number of operations performed.${resetColor}\n"

                    while true; do
                        read -rp "[!] Do you want to check the permissions of these collections anyway? [y/n] " yn
                        case "$yn" in
                            [Yy]* ) checkCollections "$2"; quit;;
                            [Nn]* ) quit;;
                            * ) echo -e "\n${yellowColor}[!] Please answer yes or no.${resetColor}\n";;
                        esac
                    done
                fi
            fi
        fi
    else
        echo -e "${redColor}[-] The specified file does not have an .apk extension.${resetColor}"
        quit
    fi
else
    echo -e "${yellowColor}[!] Usage: $(basename "$0") <APKFILE> [CREDS/TOKEN]${resetColor}"
fi