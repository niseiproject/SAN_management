#!/bin/bash

#####################################################################
#                                                                   #
#   Name: get_congestion_ports.sh                                   #
#   Date: 30/10/2017                                                #
#   Author: Jesus Gomez Email: jgomezuzq@gmail.com                  #   
#   Description: filters congestion & latency ports and gets WWNs   # 
#   & zoning involved.                                              #
#                                                                   #
#####################################################################

# grep -i -E "[[:xdigit:]]{2}(\:[[:xdigit:]]{2}){7}"

#SWITCH      SERIAL          MODEL       IP CP0          IP CP1          IP Mgmt
#DCX_C_IT3   BRCAFX0609E01B  ED-DCX-B    180.16.142.102  180.16.142.103  180.16.142.104
#DCX_C_IT4   BRCAFX0609E015  ED-DCX-B    180.16.138.25   180.16.138.26   180.16.138.27
#DCX_A_IT3   BRCAFX0609E01C  ED-DCX-B    180.16.142.96   180.16.142.97   180.16.142.98
#DCX_A_IT4   BRCAFX0604E0L0  ED-DCX-B    180.16.138.19   180.16.138.20   180.16.138.21
#DCX_D_IT3   BRCAFX0609E019  ED-DCX-B    180.16.142.105  180.16.142.106  180.16.142.107
#DCX_D_IT4   BRCAFX0610E012  ED-DCX-B    180.16.138.22   180.16.138.23   180.16.138.24
#DCX_B_IT3   BRCAFX1923M00R  ED-DCX-B    180.16.142.99   180.16.142.100  180.16.142.101
#DCX_B_IT4   BRCAFX0609E01G  ED-DCX-B    180.16.138.16   180.16.138.17   180.16.138.18

#### CONSTANTS

WORKDIR="$HOME/congestion"
KEY="$HOME/.ssh/id_dsa"
#Custom user:   userconfig --add monuser -r user -l 128,126 -d "monitoring user for scripting" -p <pass>
#               userconfig --add monuser -r user -d "monitoring user for scripting" -p <pass>
USER='monuser'
SWITCHES=''
# ENTER THE IPS OF YOUR SAN SWITCHES ACCORDING TO YOUR OWN ENVIRONMENT, SEPARATED BY BLANK SPACES.
SWITCHES_CLASSIC='X.X.X.X Y.Y.Y.Y'
SWITCHES_PREDES='X.X.X.X Y.Y.Y.Y'
SWITCHES_FLOW='X.X.X.X Y.Y.Y.Y'
SWITCHES_MERCADOS='X.X.X.X Y.Y.Y.Y'
SAN='[classic|mercados|predes|flow]'
DOMAIN='no'
VF_PROD_DOMAIN='126'
# c3Discard=[FW-1202] congestion=[AN-1004] latency="[AN-1003]|[AN-1010]"
EVENT_C3D='\[FW-1202\]'
EVENT_LAT1='\[AN-1003\]'
EVENT_LAT2='\[AN-1010\]'
EVENT_CON='\[AN-1004\]'
STATS='tim_rdy|tim_txcrd_z |tim_txcrd_z_vc  [04]|er_'
VCS='tim_txcrd_z_vc  [04]'
VC_2_3='0- 3:'
VC_4_5='4- 7:'
SUB='0-\;4-'
STAT_HEADER='Switch name;Port;Device;tim_rdy_pri;tim_txcrd_z;tim_txcrd_z_VC2;tim_txcrd_z_VC3;tim_txcrd_z_VC4;tim_txcrd_z_VC5;er_enc_in;er_crc;er_trunc;er_toolong;er_bad_eof;er_enc_out;er_bad_os;er_rx_c3_timeout;er_tx_c3_timeout;er_c3_dest_unreach;er_other_discard;er_type1_miss;er_type2_miss;er_type6_miss;er_zone_miss;er_lun_zone_miss;er_crc_good_eof;er_inv_arb'
INFO_HEADER='Switch name;Fabric ID;Port;Aliases;Connected devices' 
ZONING_HEADER='Switch;Port;Port FID;Portname;Source FID;Source alias;Source WWN;Destination FID;Destination alias;Destination WWN'
PORTWWN='portWwn:'
PRTSHOW='port(Name|Id)|[[:xdigit:]]{2}(:([[:xdigit:]]){2}){7}'
WWN='[[:xdigit:]]{2}(:([[:xdigit:]]){2}){7}'
FID='[[:xdigit:]]{6}'
ALIAS='[A-Z]{3}[A-Z,0-9,_]{2,}'
ZONEMEMBER=' [[:xdigit:]]{6}; '
ZONEFILTER='[[:xdigit:]]{6};[[:xdigit:]]{2}(:([[:xdigit:]]){2}){7}'


#### FUNCTIONS

show_syntax (){
    # SAMPLE USAGE.
    echo "$0: Usage error. The correct syntax is:"
    echo "$0: sh get_congestion_ports.sh [classic|mercados|predes|flow]"
    return 0
}

check_parameters (){
    # CHECKS GLOBAL PARAMETERS (SAN ID).
    san=$1
    if ! `echo $san | grep -i -q -E "$SAN"`
    then
        return 1
    fi
    return 0
}

get_log_data (){

    # Dumps the switch error log in search of troublesome events.
    switchip=$1
    log=$2
    domain=$3
    > $log    

    if ! `test -f $log`
    then
        return 1
    fi

    if `test $domain != $VF_PROD_DOMAIN`
    then
        ssh -i $KEY $USER@$switchip "errdump | grep -i -E \"$EVENT_C3D|$EVENT_CON|$EVENT_LAT1|$EVENT_LAT2\"" > $log 2> /dev/null
    else
        ssh -i $KEY $USER@$switchip "fosexec --fid $domain -cmd errdump" | grep -i -E "$EVENT_C3D|$EVENT_CON|$EVENT_LAT1|$EVENT_LAT2" > $log 2> /dev/null
    fi
    return 0
}

get_ports (){
    # RETRIEVES AFECTED PORTS.
    log=$1
    portlist=$2
    > $portlist

    if ! `test -f $log` || ! `test -f $portlist`
    then
        return 1
    fi

    cat $log | grep -o -E " ([[:digit:]]{1,2})/[[:digit:]]{2}" | sort -u > $portlist

    return 0
}

get_stats (){
    # COLLECTS PORT STATS.
    switchip=$1
    portlist=$2
    pstats=$3
    swn=$4
    domain=$5
    tempf=`mktemp /tmp/get_stats.XXX`

    if ! `test -f $portlist` || ! `test -f $pstats`
    then
        return 1
    fi

    for port in `cat $portlist`
    do
        if `test $domain != $VF_PROD_DOMAIN`
        then 
            pname=`ssh -i $KEY $USER@$switchip "portname $port" | awk '{print $3}'`
            ssh -i $KEY $USER@$switchip "portstatsshow $port" | grep -i -E "$STATS" > $tempf
        else
            pname=`ssh -i $KEY $USER@$switchip "fosexec --fid $domain -cmd "portname $port"" | awk '{print $3}'`
            ssh -i $KEY $USER@$switchip "fosexec --fid $domain -cmd "portstatsshow $port"" | grep -i -E "$STATS" > $tempf
        fi
        vc2_3=`cat $tempf | grep -i -E "$VC_2_3" | awk '{print $6";"$7}'`
        vc4_5=`cat $tempf | grep -i -E "$VC_4_5" | awk '{print $4";"$5}'`
        vch="$vc2_3;$vc4_5"
        statistics=`cat $tempf | grep -v -E "$VCS" | awk '{print $2}' | xargs | awk -v swname="$swn" -v prt="$port" -v name="$pname" '{gsub(/ /,";");print swname";"prt";"name";"$0}'` 
        qentry=`echo $statistics | cut -d';' -f1-5`
        qending=`echo $statistics | cut -d';' -f6-23`
        statistics="$qentry;$vch;$qending"
        echo $statistics >> $pstats
    done

    rm $tempf    

    return 0
}

get_alias(){
    # GET WWPN ALIAS, IF IT EXISTS.
    wwn=$1
    alifile=$2
    ali=`cat $alifile | grep -i alias -A1| grep -i $wwn -B1 | grep -o -E "$ALIAS"`
    echo $ali
    return 0
}


get_connected_devices (){
    # LISTS DEVICES CONNECTED TO THE SPECIFIED PORT AND THE TARGETS THEY ARE ZONED TO.
    switch=$1
    swname=$2
    aliases_f=$3
    port=$4
    fid=$5
    palias=$6
    wwns=$7
    zone_f=$8
    domain=$9

    initiators=''
    if test -z "$wwns"
    then
        return 1
    fi

    for wwn in `echo $wwns`
    do
        wwn_alias=`get_alias $wwn $aliases_f`
        
        if test -z "$wwn_alias"
        then
            initiators="$initiators$wwn (not defined),"
        else
            initiators="$initiators$wwn ($wwn_alias),"
        fi

        if `test $domain != $VF_PROD_DOMAIN`
        then
            zones=`ssh -i $KEY $USER@$switch "nszonemember $wwn" | grep -i -E "$ZONEMEMBER" | awk -F";" '{print $1";"$3}' | grep -o -E "$ZONEFILTER" | xargs`
        else
            zones=`ssh -i $KEY $USER@$switch "fosexec --fid $domain -cmd "nszonemember $wwn"" | grep -i -E "$ZONEMEMBER" | awk -F";" '{print $1";"$3}' | grep -o -E "$ZONEFILTER" | xargs`
        fi

        if ! test -z "$zones"
        then
            local_fid=`echo $zones | awk '{print $1}' | awk -F";" '{print $1}'`
            local_wwn=`echo $zones | awk '{print $1}' | awk -F";" '{print $2}'`

            for dev in `echo $zones`
            do
                dev_fid=`echo $dev | awk -F";" '{print $1}'`

                if test "$local_fid" != "$dev_fid"
                then
                    dev_wwn=`echo $dev | awk -F";" '{print $2}'`
                    dev_alias=`get_alias $dev_wwn $aliases_f`
                    echo "$swname;$port;$fid;$palias;$local_fid;$wwn_alias;$local_wwn;$dev_fid;$dev_alias;$dev_wwn" >> $zone_f
                fi
            done           
        fi
    done
    
    initiators=`echo $initiators | awk '{gsub(/,$/,"");print}'`

    if test -z "$initiators"
    then
        echo 'No devices attached to this port'
        return 1
    fi
    
    echo $initiators
    return 0
}

get_port_info (){
    # RETRIEVES PORT DETAILS.
    switchip=$1
    swn=$2
    portlist=$3
    pinfo=$4
    pzoning=$5
    aliases=$6
    domain=$7

    if ! `test -f $portlist` || ! `test -f $pinfo`
    then
        return 1
    fi

    for port in `cat $portlist`
    do
        if `test $domain != $VF_PROD_DOMAIN`
        then
            info=`ssh -i $KEY $USER@$switchip "portshow $port" | grep -i -E "$PRTSHOW" | grep -o -E "$WWN|$FID|$ALIAS" | xargs | awk '{gsub(/ /,";");print}'`
        else
            info=`ssh -i $KEY $USER@$switchip "fosexec --fid $domain -cmd "portshow $port"" | grep -i -E "$PRTSHOW" | grep -o -E "$WWN|$FID|$ALIAS" | xargs | awk '{gsub(/ /,";");print}'`
        fi
        palias=`echo $info | grep -o -E "$ALIAS"` 
        pfid=`echo $info | grep -o -E "$FID"`
        wwns=`echo $info | grep -o -E "$WWN" | xargs`
        pwwn=`echo $wwns | awk '{print $1}'`
        wwns=`echo $wwns | awk '{gsub(/'"$pwwn"'/,"");print}'`
        initiators=`get_connected_devices "$switchip" "$swn" "$aliases" "$port" "$pfid" "$palias" "$wwns" "$pzoning" "$domain"` 
        info="$swn;$pfid;$port;$palias;$initiators"
        echo $info >> $pinfo
    done

    return 0
}


#### MAIN

if `test $# -ne 1`
then
    show_syntax
    exit 1
fi

san=$1

if ! `check_parameters $san`
then
    show_syntax
    exit 1
fi

case $san in

    classic)
            SWITCHES=$SWITCHES_CLASSIC
            ;;
    mercados)
            SWITCHES=$SWITCHES_MERCADOS
            DOMAIN='126'
            ;;
    predes)
            SWITCHES=$SWITCHES_PREDES
            DOMAIN='126'
            ;;
    flow)
            SWITCHES=$SWITCHES_FLOW
            ;;
    *)
        echo "$0: Error while matching SAN network."
        exit 1
esac

now=`date +"%Y%m%d%H%M"`
portstats="$WORKDIR/"$now"_"$san"_get_congestion_ports_portstats.csv"
portinf="$WORKDIR/"$now"_"$san"_get_congestion_ports_portinfo.csv"
zoningf="$WORKDIR/"$now"_"$san"_get_congestion_ports_zoning.csv"

touch $portstats
touch $portinf
touch $zoningf

echo $STAT_HEADER > $portstats
echo $INFO_HEADER > $portinf
echo $ZONING_HEADER > $zoningf


for ip in `echo $SWITCHES`
do
    id=`echo $ip | awk '{gsub(/\./,"-");print}'`
    logdata="$WORKDIR/"$now"_"$id"_logdata.csv"
    ports="$WORKDIR/"$now"_"$id"_ports.csv"
    name=`ssh -i $KEY $USER@$ip "switchname"`

    touch $logdata
    touch $ports
    aliasesf=`mktemp /tmp/get_pinfo.XXX`

    if `test $DOMAIN != $VF_PROD_DOMAIN`
    then
        ssh -i $KEY $USER@$ip alishow > $aliasesf 2>/dev/null
    else
        ssh -i $KEY $USER@$ip "fosexec --fid $DOMAIN -cmd alishow" > $aliasesf 2>/dev/null
    fi

    if ! `get_log_data $ip $logdata $DOMAIN` 
    then
        echo "$0: Error while trying to retrieve log data."
        exit 1
    fi
    
    if ! `get_ports $logdata $ports $DOMAIN`
    then
        echo "$0: Error while trying to get troublesome ports."
        exit 1
    fi
    
    if ! `get_stats $ip $ports $portstats $name $DOMAIN`
    then
        echo "$0: Error while trying to collect port statistics."
        exit 1
    fi

    if ! `get_port_info $ip $name "$ports" $portinf $zoningf $aliasesf $DOMAIN`
    then
        echo "$0: Error while trying to get port information."
        exit 1
    fi
    
    rm $aliasesf
done

echo "$0: Report completed. All files were saved at $WORKDIR."
exit 0



