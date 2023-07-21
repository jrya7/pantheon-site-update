#!/bin/bash


## 
# functions
##
# function to display the help message
show_help() {
  echo "  Usage: $0 [SITENAME] [--no-check]"
  echo ""
  echo "  SITENAME: the site you want to update"
  echo "  --no-check: optional flag to disable update prompts"
}


# function for checking logged into terminus
# if logged in then will ask to continue as logged in account
# if not logged in then will try the terminus auth:login command
# if fails then exits and has user login first
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
		# check if the --no-check flag is provided to skip input
		if [[ "$no_check_flag" == true ]]; then
			printf "logged into terminus as $RESPONSE \n"
		else
			read -p "logged into terminus as $RESPONSE - press [y] to continue or [n] to exit: " login;
			case $login in
				[Yy]* ) ;;
				[Nn]* ) exit 0;;
			esac
		fi
	fi
}


# function to check the site for being drupal
# uses a regex to check the terminus site:info for being drupal
drupal_check() {
	# get the framework of the site and set regex
	FRAMEWORK=`terminus site:info $SITENAME --field=framework`
    ERRORS='0'
    REGEX="[drupal]"

    # check for a drupal site
    if [[ "$FRAMEWORK" =~ $REGEX ]]; then
    	# alls good so continue
    	printf "valid drupal site so continuing\n"
    # not a drupal site so exit
    else
		printf "script only works for drupal sites, exiting..."
		exit 0
    fi
}

# function to check which drupal framework is used
# uses a regex to check the terminus site:info for being drupal or drupalX
drupal_framework() {
	# get the framework of the site and set regex
	FRAMEWORK=`terminus site:info $SITENAME --field=framework`
    ERRORS='0'
    REGEX="^drupal$"

    # check for drupal as the framework
    if [[ "$FRAMEWORK" =~ $REGEX ]]; then
    	# alls good so continue
    	echo "drupal7"
    # check for a number after drupal in the framework field
    else
		echo "drupal8"
    fi
}


# function to prep the site
# can create backup of live site before updating - code, files, db
# check for being in git mode to check & apply upstream updates
drupal_prep() {
	# print out a new line for spacing
	printf '\n'

	# check if the --no-check flag is provided to skip input
	if [[ "$no_check_flag" == true ]]; then
		printf "skipping backup of live environment\n"
	else
		# ask if user wants to backup the live env first
		read -p "backup live environment? [y/n]  " yn
		case $yn in
			[Yy]* ) printf "\ncreating backup of live environment for ${SITENAME}...\n"; 
					# check for being in git mode
					CONNECTION=`terminus env:info --field connection_mode -- $SITENAME.dev`
					if [ "$CONNECTION" != "git" ]; then
						# set to git mode
						env_git
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
	fi

	# check for being in git mode
	CONNECTION=`terminus env:info --field connection_mode -- $SITENAME.dev`
	if [ "$CONNECTION" != "git" ]; then
		# set to git mode
		env_git
	fi
}


# update the drupal dev site
# check for an apply upstream updates
# if drupal7 or below site then check for module updates
# if drupal8 or above site then skip module updates
drupal_update() {
	# let the user know checking for updates
	printf "\nchecking for upstream updates...\n"

	# set the update check var to see if need to continue
	updateCheck=true

	# check for upstream updates
	upstreamCheck=`terminus upstream:updates:status -- ${SITENAME}.dev`

	# there is upstream updates
	if [ "$upstreamCheck" == "outdated" ]; then
		# let the user know there are updates
		printf "upstream updates found, gathering list...\n"

		# list the upstream updates first
		terminus upstream:updates:list --fields=datetime,message,author -- ${SITENAME}.dev

		# check if the --no-check flag is provided to skip input
		if [[ "$no_check_flag" == true ]]; then
			printf "\napplying upstream updates for ${SITENAME}...\n"; 
			terminus upstream:updates:apply --updatedb --accept-upstream -- ${SITENAME}.dev

			# done with updates so let user check
			printf "\ndev environment updated, applying to test and live"
		else
			# has upstream so ask for updates
			read -p "apply upstream updates? [y/n]  " yn
			case $yn in
				[Yy]* ) printf "\napplying upstream updates for ${SITENAME}...\n"; 
						terminus upstream:updates:apply --updatedb --accept-upstream -- ${SITENAME}.dev
						;;
				[Nn]* ) printf "\nstopping script...\n"
						exit 0;;
			esac
		fi
	# there is no upstream updates
	else
		printf "\nno upstream updates found"
		updateCheck=false
	fi

	# check for drupal version
	frameworkCheck=`drupal_framework`

	# framework is d7 so check for module updates
	if [ "$frameworkCheck" == "drupal7" ]; then
		# let the user know its d7 so checking for updates
		printf "\ndrupal7 or below site so checking for module updates"

		# switch back to sftp mode for module update checks
		env_sftp

		# inform the user of the current action
		printf "\ngrabbing module update info...\n"

		# check for updates
		terminus drush ${SITENAME}.dev -- ups

		# ask if user wants to update
		read -p "apply module updates? [y/n]  " yn
		case $yn in
			[Yy]* ) printf "\napplying module updates for ${SITENAME}...\n"; 
					# update drupal modules
					terminus drush ${SITENAME}.dev -- up
					if [ $? = 1 ]; then
						$((ERRORS++))
						printf "\n[err] error in module updates"
						UPFAIL='drush command up (module updates) failed'
					fi

					# run the database updates
					if [ -z "$UPFAIL" ]; then
						printf "\napplying database updates...\n"
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
						[Yy]* ) read -p "provide a commit to attach to this commit: " MESSAGEDEV
								terminus env:commit --message="$MESSAGEDEV" --force -- ${SITENAME}.dev
								;;
						[Nn]* ) exit 0;;
					esac
					;;
			[Nn]* ) if [[ "$updateCheck" == false ]]; then
						printf "\nno updates to apply, stopping script...\n"
						exit 0
					fi
					;;
		esac
	# framework is d8 so dont check for module updates since handled by composer
	else
		if [[ "$updateCheck" == false ]]; then
			printf "\nno updates to apply, stopping script...\n"
			exit 0
		else
			printf "\ndrupal8 or above site so update modules via composer\n"
		fi
	fi

	# done with updates so let user check
	printf "\ndev environment updated, check site if needed - https://dev-${SITENAME}.pantheonsite.io"
	
	# error checking
	errors_check
}


# push up the drupal dev site
# push changes to test & live env using commit message from prep
drupal_push() {
	# print out a new line for spacing and check with user and then move to test
	printf '\n'

	# check if the --no-check flag is provided to skip input
	if [[ "$no_check_flag" == true ]]; then
		# get the commit message
		read -p "provide a commit to attach to the deployment: " MESSAGEPREP

		# now update test & live
		printf "\napplying to test environment"
		terminus env:deploy --note="${MESSAGEPREP}" --updatedb -- ${SITENAME}.test
		terminus env:clear-cache ${SITENAME}.test
		printf "\napplying to live environment"
		terminus env:deploy --note="${MESSAGEPREP}" --updatedb -- ${SITENAME}.live
		terminus env:clear-cache ${SITENAME}.live
	else
		read -p "deploy changes to test environment on Pantheon? [y/n] " DEPLOYTEST
		case $DEPLOYTEST in
			[Yy]* ) # get the commit message
					read -p "provide a commit to attach to the deployment: " MESSAGEPREP
					terminus env:deploy --note="${MESSAGEPREP}" --updatedb -- ${SITENAME}.test
					terminus env:clear-cache ${SITENAME}.test
					;;
			[Nn]* ) exit 0;;
		esac

		# done with updates so let user check
		printf "\ntest environment updated, check site if needed - https://test-${SITENAME}.pantheonsite.io"

		# print out a new line for spacing and ask to deploy to live
		printf '\n'
		read -p "deploy changes to live environment on Pantheon? [y/n] " DEPLOYLIVE
		case $DEPLOYLIVE in
			[Yy]* ) terminus env:deploy --note="${MESSAGEPREP}" --updatedb -- ${SITENAME}.live
					terminus env:clear-cache ${SITENAME}.live
					;;
			[Nn]* ) exit 0;;
		esac
	fi
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
	printf "\nswitching to git connection mode...\n"
	terminus connection:set ${SITENAME}.dev git
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo "[err] error in switching to git\n"
	fi
}


# switch to sftp mode
env_sftp() {
	# switch back to sftp mode for module update checks
	printf "\nswitching to sftp connection mode for module updates...\n"
	terminus connection:set ${SITENAME}.dev sftp
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo "[err] error in switching to sftp"
	fi
}


##########################################


## 
# main
##
# parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-check)
      no_check_flag=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      argument="$1"
      shift
      ;;
  esac
done

# start the script with an echo message
printf "\nstarting pantheon site update\n"

# check for logged in user
terminus_auth_check

# check for site name passed
if [[ -n "$argument" ]]; then
	# set the sitename variable
	SITENAME=$argument
else
	# no arguments so get site list and input
	# grab the sites and display
	printf '\nfetching site list...\n'
	terminus site:list --fields="name,plan_name,framework"

	# print out a new line for spacing
	printf '\n'

	# set the site and start to update
	read -p 'enter a site name and press [Enter] to continue: ' SITENAME
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




