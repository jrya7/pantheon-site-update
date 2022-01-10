#!/bin/bash


# function for checking logged into terminus
terminus_auth() {
	# run the whoami terminus command
	response=`terminus auth:whoami`

	# user is not logged in
	if [ "$response" == "" ]; then
		# let the user know
		echo " [msg] you are not logged into Terminus, trying to login..."

		# try to login with terminus command
		terminus auth:login

		# is logged in success
		if [ $? -eq 0 ]; then
			echo " [msg] login successful!"
		# cant log in
		else
			echo " [msg] login failed, please try again"
			exit 0
		fi

	# user is logged in so continue
	else
		read -p " [msg] logged in as $response press [y] to continue or [n] to login as someone else: " login;
		case $login in
			[Yy]* ) ;;
			[Nn]* ) terminus auth:logout;
					terminus auth:login;;
		esac
	fi
}

# function to loop thru the update steps
step_route() {
    FRAMEWORK=`terminus site:info $SITENAME --field=framework`
    ERRORS='0'
    if [ "$FRAMEWORK" = 'drupal' ]; then
        case $STEP in
                [start]* ) multidev_drupal_update $SITENAME;;
                [finish]* ) multidev_finish $SITENAME;;
                * ) echo " not a valid function, exiting..."; exit 1;;
        esac
    fi
}

# function to create multidev env to hold the updates
multidev_update_prep() {
	printf "\n creating or updating multidev for site -- ${SITENAME}\n"

	# set the multidev env name
	MDENV='env-term'

	# ask if user wants to backup the live env first
	read -p " backup live? [y/n]  " yn
	case $yn in
		[Yy]* ) printf "\n [msg] creating backup of live environment for ${SITENAME}...\n"; 
				terminus backup:create ${SITENAME}.live;;
	esac

	# check for erros in backing up
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo " [err] error in making backup of live environment"
		exit 0
	fi

	# check if multidev is created
	envExist=`terminus env:list ${SITENAME} | grep "${MDENV}"`

	# multidev not created
	if [ -z "$envExist" ]; then
		# start to create the multidev env
		printf "\n [msg] creating multidev env-term enironment\n"

		# get the env to pull the db from
		read -p " pull down db from which environment? [dev/test/live] "	FROMENV

		# create the multidev and check for errors
		terminus multidev:create ${SITENAME}.${FROMENV} ${MDENV}
		if [ $? = 1 ]; then
			$((ERRORS++))
			echo "\n [err] error in creating multidev environment"
		fi
	# multidev already created
	else
		read -p "\n [msg] multidev ${MDENV} environment already exists \n pull down db from which environment? [dev/test/live/none] " FROMENV
		if [ $FROMENV != 'none' ]; then
			# clone the selected environment into the multidev
			terminus env:clone-content --cc --updatedb -- $SITENAME.$FROMENV $MDENV
		fi
	fi

	# output the multidev environment to the user for testing
	printf "\n multidev environment created - https://${MDENV}-${SITENAME}.pantheonsite.io"


	# set to git mode
	printf "\n [msg] switching to git connection-mode...\n"
	terminus connection:set ${SITENAME}.${MDENV} git
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo " [msg] error in switching to git"
	fi
}

# function to start updating
multidev_drupal_update() {
	# setup or update multidev
	multidev_update_prep

	# check for upstream updates
	upstreamCheck=`terminus upstream:updates:status -- ${SITENAME}.${MDENV}`

	# there is upstream updates
	if [ "$upstreamCheck" == "outdated" ]; then
		# let the user know there are updates
		printf "\n [msg] upstream updates found, gathering list...\n"

		# list the upstream updates first
		terminus upstream:updates:list --fields=datetime,message,author -- ${SITENAME}.${MDENV}

		# has upstream so ask for updates
		read -p " apply upstream updates? [y/n]  " yn
		case $yn in
			[Yy]* ) printf "\n [msg] applying upstream updates for ${SITENAME}...\n"; 
					terminus upstream:updates:apply --updatedb --accept-upstream -- ${SITENAME}.${MDENV}
		esac
	# there is no upstream updates
	else
		printf "\n [msg] no upstream updates found"
	fi

	# switch back to sftp mode for module update checks
	printf "\n [msg] switching to sftp connection-mode for module updates..."
	terminus connection:set ${SITENAME}.${MDENV} sftp
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo " [msg] error in switching to sftp"
	fi

	# inform the user of the current action
	printf "\n [msg] grabbing for module info...\n"

	# check for updates
	terminus drush ${SITENAME}.${MDENV} -- ups

	# ask if user wants to update
	read -p " apply module updates? [y/n]  " yn
	case $yn in
		[Yy]* ) printf "\n [msg] applying module updates for ${SITENAME}...\n"; 
				# update drupal modules
				terminus drush ${SITENAME}.${MDENV} -- up
				if [ $? = 1 ]; then
					$((ERRORS++))
					printf "\n [msg] error in module updates"
					UPFAIL='Drush up failed.'
				fi

				# run the database updates
				if [ -z "$UPFAIL" ]; then
					printf "\n [msg] applying database updates...\n"
					terminus drush ${SITENAME}.${MDENV} -- updb
					if [ $? = 1 ]; then
						$((ERRORS++))
						printf "\n [msg] error in database updates"
						UPDBFAIL='Drush updb failed.'
					fi
				fi
	esac

	# done with updates so let user check
	printf "\n multidev environment updated - https://${MDENV}-${SITENAME}.pantheonsite.io \n"
	

	# error checking
	multidev_update_errors
}


# check for errors and output
multidev_update_errors() {
	if [ $ERRORS != '0' ]; then
		WORD='error was'
		if [ $ERRORS > '1' ]; then
			WORD='errors were'
		fi
		echo " [err] $ERRORS $WORD reported, scroll up and look for the red"
	fi
}


# merge the multidev environment into dev
multidev_merge() {
	# use terminus merge-to-dev to merge multidev into dev
	terminus multidev:merge-to-dev --updatedb -- ${SITENAME}.${MDENV}

	# let the user know
	printf "\n multidev merged into dev - https://dev-${SITENAME}.pantheonsite.io \n"
}


# deploy from dev to test
multidev_deploy_to_test() {
	read -p " deploy changes to test environment on Pantheon? MAKE SURE DEV IS SYNCHED FIRST [y/n] " DEPLOYTEST
	case $DEPLOYTEST in
		[Yy]* ) read -p " provide a note to attach to this deployment: " MESSAGE
				terminus env:deploy --note="$MESSAGE" --updatedb -- ${SITENAME}.test
				terminus env:clear-cache ${SITENAME}.test
				;;
		[Nn]* ) exit 0;;
	esac
}


# deploy from test to live
multidev_deploy_to_live() {
	# print out a new line for spacing
	printf '\n'

	read -p " deploy changes to live environment on Pantheon? MAKE SURE TEST IS SYNCHED FIRST [y/n] " DEPLOYLIVE
	case $DEPLOYLIVE in
		[Yy]* ) read -p " provide a note to attach to this deployment: " MESSAGE
				terminus env:deploy --note="$MESSAGE" --updatedb -- ${SITENAME}.live
				terminus env:clear-cache ${SITENAME}.live
				;;
		[Nn]* ) exit 0;;
	esac
}


# finish up with things
multidev_finish() {
	SITE=$1
	MDENV='env-term'
	SITEINFO=`terminus site:info ${SITENAME} --field=id`
	SITEID=${SITEINFO#*: }
	GITURL="ssh://codeserver.dev.${SITEID}@codeserver.dev.${SITEID}.drush.in:2222/~/repository.git"

	# TODO - TEST IF COMMIT NEEDED AFTER DRUPAL MODULE UPDATES
	# get the message for the commits and commit
    #read -p " provide commit message: " MESSAGE
    #terminus env:commit ${SITENAME}.${MDENV} --message="$MESSAGE" 

    # check for errors
    #if [ $? -ne 0 ]; then
	#    echo " [err] git commit failed"
	#    exit 1
    #fi

    # set to git mode
	printf "\n [msg] switching to git connection-mode...\n"
	terminus connection:set ${SITENAME}.${MDENV} git
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo " [msg] error in switching to git"
	fi
	

	# merge to git and make pantheon cycles
	multidev_merge
	multidev_deploy_to_test
	multidev_deploy_to_live


	# finish by deleting multidev
	read -p " delete env-term multidev? [y/n]  " yn
	case $yn in
		[Yy]* ) terminus multidev:delete --delete-branch --yes -- ${SITENAME}.${MDENV}
	esac

}


# check for logged in user
terminus_auth


# grab the sites and display
printf '\n loading site list...\n'
terminus site:list --fields="name,plan_name,framework,ID"

# print out a new line for spacing
printf '\n'

# set the site and start to update
read -p ' enter a site name and press [Enter] to start updating: ' SITENAME
STEP='start'
step_route


# final steps
read -p " press [Enter] to finish updating ${SITENAME}" 
STEP='finish'
step_route

# cleaing up terminus
read -p ' [msg] log out of Terminus? [y/n] ' LOGOUT
  case $LOGOUT in
        [Yy]* ) terminus auth:logout
  esac


# output site updated
printf "\n ${SITENAME} updated!!\n\n"

exit 0