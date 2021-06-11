#!/bin/bash
##########
## Author: Srikant Noorani @Broadcom.com
## Simple Mult Tenant Data Collector 
## Date: Apr 2021
## Need to add error checking etc. MIT License
#############

getMetricData () {
	#AGENT_NAME='.*'
	#METRIC_EXPR='Frontends\\|Apps\\|TIXCHANGE Web\\|URLs\\|.*:Average Response Time \\(ms\\)'

	AGENT_NAME="$1"
	METRIC_EXPR="$2"
	START_TIME="$3"
	DURATION="$4"
	END_TIME=`expr $START_TIME + $DURATION \* 60000`

	AGENT_NAME=$(echo "$AGENT_NAME"|sed 's/\\/\\\\/g')
	METRIC_EXPR=$(echo "$METRIC_EXPR"|sed 's/\\/\\\\/g')

	#echo " AN is $AGENT_NAME --- ME is $METRIC_EXPR"

	METRIC_DATA=`curl -s -k -X POST 'https://apmgw.dxi-na1.saas.broadcom.com/126/apm/appmap/private/apmData/query' \
	-H 'Authorization: Bearer eyJJKV1QiLCJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJTUklLQU5ULk5PT1JBTklAQlJPQURDT00uQ09NIiwiZHluZXhwIjp0VlLCJ0aWQiOjEwMjYsImp0aSI6ImFhZTc0ZDYyLTExMzMtNGI2Mi1hNWQ1LTlmYzdkZTAzMTIwYSJ9.1k0kCEQF1U55RGfZtc37EgIdTC8l8tIFFvScfjyzwDTohUOBqbe209iq43Zm1TeY93DOrlSS98gD0VrhARX84g' \
	-H 'Content-Type: application/json' \
	-d '{"query":"SELECT domain_name, agent_host,agent_process, agent_name, metric_path,  metric_attribute, ts, min_value, max_value, agg_value, value_count, frequency FROM metric_data WHERE ts >= '$START_TIME' AND ts <= '$END_TIME' AND agent_name like_regex '\'"$AGENT_NAME"\'' AND metric_path like_regex '\'"$METRIC_EXPR"\'' AND value_count > 0 limit 5"}'`

	echo "$METRIC_DATA"
}


OUTPUT_FOLDER=output
METRIC_DATA_FILE=$OUTPUT_FOLDER/metricData.json
QUERY_FILE=$OUTPUT_FOLDER/query.sql

mkdir $OUTPUT_FOLDER 2> /dev/null

echo "" > $METRIC_DATA_FILE
echo "" > $QUERY_FILE

echo ""
echo "Specify your tenant token"
read TOKEN

echo ""
echo "Specify your tenant name"
read TENANT_NAME

echo ""
echo "Specify your App Name"
read APP_NAME

echo ""
echo "Specify Start time - YYYY-MM-DD HH:MM:SS. For e.g.`date "+%Y-%m-%d %H:00:00"`"
read START_TIME
START_TIME=`date -d "$START_TIME" +"%s"`
START_TIME="${START_TIME}000"


echo ""
echo "Specify the duration in minutes. For e.g 60"
read DURATION

echo ""
echo "Specify your agent name regex. For e.g. .*<AgentName>.*"
read AGENT_NAME

echo ""
echo "Specify your metric expr regex. For e.g. Frontends\\\\|Apps\\\\|TIXCHANGE Web\\\\|URLs.*:Average Response Time \\\\(ms\\\\)"
read METRIC_EXPR


#METRIC_DATA=$(getMetricData '.*TxChangeWeb_UC1.*' 'Frontends\\|Apps\\|TIXCHANGE Web\\|URLs\\|.*:Average Response Time \\(ms\\)') 
METRIC_DATA=`getMetricData "$AGENT_NAME" "$METRIC_EXPR" "$START_TIME" "$DURATION"` 

echo "$METRIC_DATA" >> $METRIC_DATA_FILE


ROW_COUNT=`cat $METRIC_DATA_FILE |./jq-linux64 '.rows'|./jq-linux64 length`

echo "ROW COUNT IS $ROW_COUNT"

COUNT=0

while [ $COUNT -lt $ROW_COUNT ];
do

	echo ""
	echo ""
	AGENT_STRING=`cat $METRIC_DATA_FILE|./jq-linux64 '.rows['$COUNT']'|sed -n 2,5p|sed 's/,/|/g'|tr -d '\n," ^ '|sed -r 's/(.*)\|/\1"/g'|sed 's/^/"/g'|sed 's/"/'\''/g'`
	echo "AGENT STRING IS $AGENT_STRING"
	
	METRIC_STRING=`cat $METRIC_DATA_FILE|./jq-linux64 '.rows['$COUNT']'|sed -n 6p|tr -d ','|sed 's/"/'\''/g'`
	echo "METRIC STRING IS $METRIC_STRING"

	METRIC_TIME=`cat $METRIC_DATA_FILE|./jq-linux64 '.rows['$COUNT']'|sed -n 8p|tr -d ',^ '`
	METRIC_TIME=`echo $METRIC_TIME|cut -c1-10`
	METRIC_TIME=`date -d @$METRIC_TIME "+%Y-%m-%d %H:%M:%S"`
	METRIC_TIME=`echo "'$METRIC_TIME'"`
	echo "METRIC TIME IS $METRIC_TIME"

	METRIC_VALUE=`cat $METRIC_DATA_FILE|./jq-linux64 '.rows['$COUNT']'|sed -n 11p|tr -d ',^ '`
	METRIC_VALUE=`echo "'$METRIC_VALUE'"`
	echo "METRIC VALUE IS $METRIC_VALUE"

	METRIC_COUNT=`cat $METRIC_DATA_FILE|./jq-linux64 '.rows['$COUNT']'|sed -n 12p|tr -d ',^ '`
	METRIC_COUNT=`echo "'$METRIC_COUNT'"`
	echo "METRIC COUNT IS $METRIC_COUNT"

	echo 'INSERT INTO `UPS_NAAS`.`METRIC_STORE` (  `agent_path`, `metric_path`, `value`, `frequency`, `count`, `tenant_name`, `start_time`, `application_name`) VALUES ( '$AGENT_STRING', '$METRIC_STRING', '$METRIC_VALUE', '1500', '$METRIC_COUNT', '\'$TENANT_NAME\'', '$METRIC_TIME', '\'$APP_NAME\'');' >> $QUERY_FILE


	echo ""
	echo "**** Done Count $COUNT of $ROW_COUNT"
	COUNT=`expr $COUNT + 1`

	sleep 1

done


MYSQL_CONT_ID=`docker ps -a |grep mysq|awk '{print $1}'`
echo "mysql -u root --database=UPS_NAAS < /tmp/query.sql" > output/runQuery.sh
chmod 755 output/runQuery.sh
docker cp output/runQuery.sh  $MYSQL_CONT_ID:/tmp/
docker cp   $QUERY_FILE $MYSQL_CONT_ID:/tmp/
docker exec -it $MYSQL_CONT_ID sh -c "/tmp/runQuery.sh"
