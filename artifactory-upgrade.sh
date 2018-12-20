#!/bin/bash

SILENT_ENABLE="false"

function user_input
{

	printf "Please Enter the artifactory Home\n"
	read ARTIFACTORY_HOME
	printf "Is it an Online Installation (y/n)\n"
	read INSTALLATION_TYPE
	printf "Please Enter the Required Artifactory Version\n"
	read JFROGVERSION
	if [ $INSTALLATION_TYPE == "n" ]
	then
		printf "Please Enter the location of Artifactory zip file\n"
		read ZIP_FILE_LOCATION
	fi
#	printf "Do you want to implement Artifactory as a service (y/n)\n"
#	read SERVICE_FLAG
	
}

function validation
{
	if [ ! -d "$ARTIFACTORY_HOME" ]
	then
		printf "ARTIFACTORY_HOME ($ARTIFACTORY_HOME) does not exist\n"
		exit 0
	fi
	if [ $INSTALLATION_TYPE != "n" !! $INSTALLATION_TYPE != "y" ]
	then
		printf "Invalid Installation type\n"
		exit 0
	fi
	if [ $INSTALLATION_TYPE == "n" ]
	then
		if [ ! -d "$ZIP_FILE_LOCATION" ]
		then
			printf "ZIP FILE LOCATION ($ZIP_FILE_LOCATION) does not exist\n"
			exit 0
		fi		
	fi


}

function download
{

	mkdir -p $ARTIFACTORY_HOME/artifactory-upgrade/backup-$JFROGVERSION
	ARTIFACTORY_BKP=$ARTIFACTORY_HOME/artifactory-upgrade/backup-$JFROGVERSION/
	if [ $INSTALLATION_TYPE == "y" ]
	then
		link_check=`curl -Is https://bintray.com/jfrog/artifactory-pro/download_file?file_path=org/artifactory/pro/jfrog-artifactory-pro/$JFROGVERSION/jfrog-artifactory-pro-$JFROGVERSION.zip | cut -d' ' -f2 | head -1`
		if [ $link_check != "302" ]
		then
			printf "Unable to download Artifactory. Please make sure the version do exist and this machine has access to Internet\n"
			exit 0
		fi
		printf "\n\nDownloading the new artifactory version ...\n\n"
		wget -q https://bintray.com/jfrog/artifactory-pro/download_file?file_path=org/artifactory/pro/jfrog-artifactory-pro/$JFROGVERSION/jfrog-artifactory-pro-$JFROGVERSION.zip -O $ARTIFACTORY_HOME/artifactory-upgrade/artifactory && cd $ARTIFACTORY_HOME/artifactory-upgrade/
		ARTIFACTORY_HOME_TMP=$ARTIFACTORY_HOME/artifactory-upgrade/artifactory-pro-$JFROGVERSION
		printf "\n\nExtracting the Artifactory zip file ...\n\n"
		unzip -q $ARTIFACTORY_HOME/artifactory-upgrade/artifactory && rm -rf $ARTIFACTORY_HOME/artifactory-upgrade/artifactory
	else
		ZIP_FILE=`echo $ZIP_FILE_LOCATION | rev | cut -d'/' -f1 | rev`
		ZIP_LOCATION=`echo $ZIP_FILE_LOCATION | rev | cut -d'/' -f2- | rev`
		ARTIFACTORY_HOME_TMP=$ZIP_LOCATION/artifactory-pro-$JFROGVERSION
		printf "\n\nExtracting the Artifactory zip file ...\n\n"
		cd $ZIP_LOCATION && unzip -q $ZIP_FILE

	fi

}

function backup
{
	printf "\n\nCreating backup at $ARTIFACTORY_HOME/artifactory-upgrade ...\n\n"
	cp $ARTIFACTORY_HOME/tomcat/conf/server.xml $ARTIFACTORY_BKP
	cp $ARTIFACTORY_HOME/bin/artifactory.default $ARTIFACTORY_BKP
	cp $ARTIFACTORY_HOME/tomcat/lib/mysql*.jar $ARTIFACTORY_HOME/tomcat/lib/*mariadb*.jar $ARTIFACTORY_HOME/tomcat/lib/*postgresql*.jar $ARTIFACTORY_HOME/tomcat/lib/*sqljdbc*.jar $ARTIFACTORY_HOME/tomcat/lib/*ojdbc*.jar $ARTIFACTORY_BKP 2>/dev/null || :
	cp -r $ARTIFACTORY_HOME/webapps/artifactory.war $ARTIFACTORY_HOME/webapps/access.war $ARTIFACTORY_HOME/tomcat $ARTIFACTORY_HOME/bin $ARTIFACTORY_HOME/misc $ARTIFACTORY_HOME/etc $ARTIFACTORY_BKP 2>/dev/null || :
	rm -rf $ARTIFACTORY_HOME/webapps/artifactory.war $ARTIFACTORY_HOME/webapps/access.war $ARTIFACTORY_HOME/tomcat $ARTIFACTORY_HOME/bin $ARTIFACTORY_HOME/misc
}

function Configuration_check
{	
	printf "\n\nModifying server.xml file ...\n\n"
	cd $ARTIFACTORY_BKP
	cp server.xml new-server.xml
	VERSION=`echo "${JFROGVERSION//.}" | cut -c1-3`
	if [ $VERSION -ge 540 ] 
	then 
		count=`cat new-server.xml | grep "Host name=" | grep startStopThreads | wc -l`
		if [ $count -eq 0 ]
		then 
			sed -i 's:appBase="webapps":& startStopThreads=\"2\":' new-server.xml
		fi
		no_threads=`cat new-server.xml | grep appBase | grep startStopThreads | awk -F 'startStopThreads="'  '{print $2}' | cut -c1`
		if [ $no_threads -lt 2 ]
		then
			orginal_no=startStopThreads=\"$no_threads\"
			ideal_no=startStopThreads=\"2\"
			sed -i "s:$orginal_no:$ideal_no:" new-server.xml
		fi

		if [ $VERSION -ge 561 ] 
		then 
			sed -i 's:sendReasonPhrase="[a-z]*"::' new-server.xml
			sed -i 's:Connector port="[0-9]*":& sendReasonPhrase="true":' new-server.xml
			if [ $VERSION -ge 570 ]
			then 
					no_of_connectors=`cat new-server.xml | sed 's/<!--/\x0<!--/g;s/-->/-->\x0/g' | grep -zv '^<!--' | tr -d '\0'| grep "Connector port" | grep -v "protocol" | wc -l`
					if (( $no_of_connectors < 2))
					then
                        awk '/<Service name="Catalina"/{print;print "\t<Connector port=\"8040\" sendReasonPhrase=\"true\" maxThreads=\"50\"/>";next}1' new-server.xml > new1-server.xml
                        mv new1-server.xml new-server.xml
					fi
				#	if [$VERSION -ge 630]
				#	then
				#		sed "s:relaxedPathChars=.* ::g" new-server.xml

				#	fi

			fi  
		fi  
	fi

}

function restore
{
	printf "\n\nUpgrading the files and folders to new version ...\n\n"
	cp -r $ARTIFACTORY_HOME_TMP/webapps/* $ARTIFACTORY_HOME/webapps/
	cp -r $ARTIFACTORY_HOME_TMP/tomcat/ $ARTIFACTORY_HOME/tomcat
	cp -r $ARTIFACTORY_HOME_TMP/bin $ARTIFACTORY_HOME/bin
	cp -r $ARTIFACTORY_HOME_TMP/misc $ARTIFACTORY_HOME/misc
	Configuration_check
	cp $ARTIFACTORY_BKP/new-server.xml $ARTIFACTORY_HOME/tomcat/conf/server.xml
	cp $ARTIFACTORY_BKP/artifactory.default $ARTIFACTORY_HOME/bin/
	cp $ARTIFACTORY_BKP/*mysql*.jar $ARTIFACTORY_BKP/*mariadb*.jar $ARTIFACTORY_BKP/*postgresql*.jar $ARTIFACTORY_BKP/*sqljdbc*.jar $ARTIFACTORY_BKP/*ojdbc*.jar $ARTIFACTORY_HOME/tomcat/lib/ 2>/dev/null || :
	sleep 10
}


function permission_check
{
	file=$1
	if [ ! -w $file ]
	then
		printf "\n!! Insufficent Permissions !!\n"
		printf "Kindly make sure the current user has read and write permissions to the ARTIFACTORY_HOME [ $ARTIFACTORY_HOME ]\n"
		exit 0
	fi
}

function backup-bundle
{
	rm -rf $ARTIFACTORY_HOME_TMP

	timestamp=$(date "+%Y.%m.%d-%H.%M.%S")

	cd $ARTIFACTORY_HOME/artifactory-upgrade && tar -cf upgrade-backup-$timestamp.tar backup-$JFROGVERSION && cd

	rm -rf $ARTIFACTORY_BKP
}


if [ $SILENT_ENABLE == "true" ]
then
        source artifactory-env.sh
else
        user_input
fi


validation
download

permission_check $ARTIFACTORY_HOME
permission_check $ARTIFACTORY_BKP
permission_check $ARTIFACTORY_HOME/webapps
permission_check $ARTIFACTORY_HOME/tomcat
permission_check $ARTIFACTORY_HOME/bin
permission_check $ARTIFACTORY_HOME/misc

##Stopping the Artifactory
printf "\n\n!! Stopping Artifactory !!\n\n"
cd $ARTIFACTORY_HOME/bin && ./artifactoryctl stop >> /dev/null
backup  ##Backing up required files
restore  ##Restoring with new files



#if [ $SERVICE_FLAG == "y" ]
#then
#	printf "Implementation of Service needs root privileges ,Kindly make sure the current User has sudo privileges\n\n Please enter the password\n"
#	cd $ARTIFACTORY_HOME/bin && sudo ./installService.sh
#fi
printf "\n\n!! Starting Artifactory !!\n\n"
cd $ARTIFACTORY_HOME/bin && ./artifactory.sh start >> /dev/null

backup-bundle
