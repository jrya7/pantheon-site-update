#!/bin/bash


## 
# functions
##
# function for checking logged into terminus
terminus_auth_check() {
	# run the whoami terminus command
	RESPONSE=`terminus auth:whoami`

	# user is not logged in
	if [ "$RESPONSE" == "" ]; then
		# let the user know
		echo "you are not logged into Terminus, trying to login..."

		# try to login with terminus command
		terminus auth:login

		# is logged in success
		if [ $? -eq 0 ]; then
			echo "login successful!"
		# cant log in
		else
			echo "login failed, please login first and try again"
			exit 0
		fi

	# user is logged in so continue
	else
		read -p "logged in as $RESPONSE - press [y] to continue or [n] to exit: " login;
		case $login in
			[Yy]* ) ;;
			[Nn]* ) exit 0;;
		esac
	fi
}


# function to check the site for being drupal
drupal_check() {
	# get the framework of the site and set regex
	FRAMEWORK=`terminus site:info $SITENAME --field=framework`
    ERRORS='0'
    REGEX="[drupal]"

    # check for a drupal site
    if [[ "$FRAMEWORK" =~ $REGEX ]]; then
    	# alls good so continue
    	echo "valid drupal site so continuing..."
    # not a drupal site so exit
    else
		echo "script only works for drupal sites, exiting..."
		exit 0
    fi
}


# function to prep the site
drupal_prep() {
	# print out a new line for spacing
	printf '\n'

	# ask if user wants to backup the live env first
	read -p "backup live environment? [y/n]  " yn
	case $yn in
		[Yy]* ) printf "\n[msg] creating backup of live environment for ${SITENAME}...\n"; 
				# check for being in git mode
				CONNECTION=`terminus env:info --field connection_mode -- $SITENAME.dev`
				if [ "$CONNECTION" != "git" ]; then
					# set to git mode
					printf "\n[msg] switching to git connection-mode...\n"
					terminus connection:set ${SITENAME}.dev git
					if [ $? = 1 ]; then
						$((ERRORS++))
						echo "[msg] error in switching to git"
						exit 0
					fi
				fi
				# backup live
				terminus backup:create ${SITENAME}.live;;
	esac

	# check for errors in backing up
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo "[err] error in making backup of live environment"
		exit 0
	fi

	# check for being in git mode
	CONNECTION=`terminus env:info --field connection_mode -- $SITENAME.dev`
	if [ "$CONNECTION" != "git" ]; then
		# set to git mode
		env_git
	fi
}


# update the drupal dev site
drupal_update() {
	# let the user know checking for updates
	printf "\nchecking for upstream updates\n"

	# check for upstream updates
	upstreamCheck=`terminus upstream:updates:status -- ${SITENAME}.dev`

	# there is upstream updates
	if [ "$upstreamCheck" == "outdated" ]; then
		# let the user know there are updates
		printf "upstream updates found, gathering list...\n"

		# list the upstream updates first
		terminus upstream:updates:list --fields=datetime,message,author -- ${SITENAME}.dev

		# has upstream so ask for updates
		read -p "apply upstream updates? [y/n]  " yn
		case $yn in
			[Yy]* ) printf "\n[msg] applying upstream updates for ${SITENAME}...\n"; 
					terminus upstream:updates:apply --updatedb --accept-upstream -- ${SITENAME}.dev
		esac
	# there is no upstream updates
	else
		printf "\n[msg] no upstream updates found"
	fi

	# switch back to sftp mode for module update checks
	env_sftp

	# inform the user of the current action
	printf "\n[msg] grabbing module update info...\n"

	# check for updates
	terminus drush ${SITENAME}.dev -- ups

	# ask if user wants to update
	read -p "apply module updates? [y/n]  " yn
	case $yn in
		[Yy]* ) printf "\n[msg] applying module updates for ${SITENAME}...\n"; 
				# update drupal modules
				terminus drush ${SITENAME}.dev -- up
				if [ $? = 1 ]; then
					$((ERRORS++))
					printf "\n[err] error in module updates"
					UPFAIL='drush command up (module updates) failed'
				fi

				# run the database updates
				if [ -z "$UPFAIL" ]; then
					printf "\n[msg] applying database updates...\n"
					terminus drush ${SITENAME}.dev -- updb
					if [ $? = 1 ]; then
						$((ERRORS++))
						printf "\n[err] error in database updates"
						UPDBFAIL='drush command updb (database updates) failed'
					fi
				fi

				# commit changes before pushing
				read -p "commit changes to dev environment on Pantheon? [y/n] " DEPLOYDEV
				case $DEPLOYDEV in
					[Yy]* ) read -p "provide a note to attach to this commit: " MESSAGEDEV
							terminus env:commit --message="$MESSAGEDEV" --force -- ${SITENAME}.dev
							;;
					[Nn]* ) exit 0;;
				esac

	esac

	# done with updates so let user check
	printf "\ndev environment updated, check site if needed - https://dev-${SITENAME}.pantheonsite.io \n"
	
	# error checking
	errors_check
}


# push up the drupal dev site
drupal_push() {
	# check with user and then move to test
	read -p "deploy changes to test environment on Pantheon? [y/n] " DEPLOYTEST
	case $DEPLOYTEST in
		[Yy]* ) read -p "provide a note to attach to this deployment: " MESSAGE
				terminus env:deploy --note="$MESSAGE" --updatedb -- ${SITENAME}.test
				terminus env:clear-cache ${SITENAME}.test
				;;
		[Nn]* ) exit 0;;
	esac

	# print out a new line for spacing
	printf '\n'

	read -p "deploy changes to live environment on Pantheon? [y/n] " DEPLOYLIVE
	case $DEPLOYLIVE in
		[Yy]* ) read -p "provide a note to attach to this deployment: " MESSAGE
				terminus env:deploy --note="$MESSAGE" --updatedb -- ${SITENAME}.live
				terminus env:clear-cache ${SITENAME}.live
				;;
		[Nn]* ) exit 0;;
	esac
}


# check for errors and output
errors_check() {
	if [ $ERRORS != '0' ]; then
		WORD='error was'
		if [ $ERRORS > '1' ]; then
			WORD='errors were'
		fi
		echo "[err] $ERRORS $WORD reported, scroll up and look for the red"
	fi
}


# switch to git mode
env_git() {
	# set back to git mode
	printf "\n[msg] switching to git connection-mode...\n"
	terminus connection:set ${SITENAME}.dev git
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo "[err] error in switching to git\n"
	fi
}


# switch to sftp mode
env_sftp() {
	# switch back to sftp mode for module update checks
	printf "\n[msg] switching to sftp connection-mode for module updates...\n"
	terminus connection:set ${SITENAME}.dev sftp
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo "[msg] error in switching to sftp"
	fi
}


##########################################


## 
# main
##
# start the script with an echo message
echo "starting pantheon site update..."

# check for logged in user
terminus_auth_check

# check for site name passed
 if [ "$#" -eq  "0" ]; then
 	# no arguments so get site list and input
 	# grab the sites and display
	printf '\nfetching site list...\n'
	terminus site:list --fields="name,plan_name,framework,ID"

	# print out a new line for spacing
	printf '\n'

	# set the site and start to update
	read -p 'enter a site name and press [Enter] to continue: ' SITENAME
else
	# set the sitename variable
	SITENAME=$1
fi

# check the site for being drupal
drupal_check

# prep the drupal site
drupal_prep

# update the drupal site
drupal_update

# push up the drupal site
drupal_push

# output site updated
printf "\n${SITENAME} updated!!\n\n"

exit 0




