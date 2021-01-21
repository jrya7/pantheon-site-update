#!/bin/bash


terminus_auth() {
	response=`terminus auth:whoami`
	if [ "$response" == "" ]; then
		echo "You are not authenticated with Terminus..."
		terminus auth:login
		if [ $? -eq 0 ]; then
    		        echo "Login successful!"
		else
    			echo "Login failed. Please re-run the script and try again."
			exit 0
		fi
	else
		read -p "Logged in as $response - [y]Continue or [n]login as someone else? [y/n] " login;
		case $login in
			[Yy]* ) ;;
			[Nn]* ) terminus auth:logout;
					terminus auth:login;;
		esac
	fi
}

step_route() {
    FRAMEWORK=`terminus site:info $SITENAME --field=framework`
    ERRORS='0'
    if [ "$FRAMEWORK" = 'drupal' ]; then
            case $STEP in
                    [start]* ) multidev_drupal_update $SITENAME;;
                    [finish]* ) multidev_finish $SITENAME;;
                    * ) echo "not a valid function."; exit 1;;
            esac
    fi
}

multidev_update_prep() {
	printf "\nCreating or updating multidev for site -- ${SITENAME}\n"
	MDENV='env-term'

	read -p "Backup live? [y/n]  " yn
	case $yn in
		[Yy]* ) printf "\nCreating backup of live environment for ${SITENAME}...\n"; 
				terminus backup:create ${SITENAME}.live;;
	esac
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo "error in backup live"
	fi

	# check if multidev is created
	envExist=`terminus env:list ${SITENAME} | grep "${MDENV}"`

	# multidev not created
	if [ -z "$envExist" ]; then
		printf "\nCreating multidev env-term enironment...\n"
		read -p "Pull down db from which environment? (dev/test/live) "	FROMENV
		terminus multidev:create ${SITENAME}.${FROMENV} ${MDENV}
		if [ $? = 1 ]; then
			$((ERRORS++))
			echo "error in creating env"
		fi
	# multidev created
	else
		read -p "Multidev env-term environment already exists.  Deploy db from environment or none (dev/test/live/none) " FROMENV
		if [ $FROMENV != 'none' ]; then
			terminus env:clone-content --cc --updatedb -- $SITENAME.$FROMENV $MDENV
		fi
	fi

	printf "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\nThe URL for the new environment is http://${MDENV}-${SITENAME}.pantheonsite.io/\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n"

	# TODO may remove or check
	echo "Switching to sftp connection-mode..."
	terminus connection:set ${SITENAME}.${MDENV} sftp
	if [ $? = 1 ]; then
		$((ERRORS++))
		echo "error in switching to sftp"
	fi

}

multidev_drupal_update() {
	# setup or update multidev
	multidev_update_prep

	# check for upstream updates
	upstreamCheck=`terminus upstream:updates:status -- ${SITENAME}.${MDENV}`
	if [ "$upstreamCheck" == "outdated" ]; then
		# has upstream so ask for updates
		read -p "Apply upstream updates? [y/n]  " yn
		case $yn in
			[Yy]* ) printf "\nSwitching to git connection-mode...\n"
					terminus connection:set ${SITENAME}.${MDENV} git
					if [ $? = 1 ]; then
						$((ERRORS++))
						printf "\nerror in switching to git"
					fi
					printf "\nApplying upstream updates for ${SITENAME}...\n"; 
					terminus upstream:updates:apply --updatedb --accept-upstream -- ${SITENAME}.${MDENV}

					printf "\nSwitching to sftp connection-mode...\n"
					terminus connection:set ${SITENAME}.${MDENV} sftp
					if [ $? = 1 ]; then
						$((ERRORS++))
						printf "\nerror in switching to sftp"
					fi
		esac
	else
		printf "\nNo upstream updates found\n"
	fi

	printf "\nChecking for module updates...\n"

	# update drupal modules
	terminus drush ${SITENAME}.${MDENV} -- up
	if [ $? = 1 ]; then
		$((ERRORS++))
		printf "\nerror in drush up"
		UPFAIL='Drush up failed.'
	fi

	if [ -z "$UPFAIL" ]; then
		printf "\nRunning 'drush updb'...\n"
		terminus drush ${SITENAME}.${MDENV} -- updb
		if [ $? = 1 ]; then
			$((ERRORS++))
			printf "\nerror in updb"
			UPDBFAIL='Drush updb failed.'
		fi
		printf "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\nSite has been updated on $MDENV multidev site, test it here - http://${MDENV}-${SITENAME}.pantheonsite.io/\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n\n"
	fi

	# error checking
	multidev_update_errors
}

multidev_update_errors() {
	if [ $ERRORS != '0' ]; then
		WORD='error was'
		if [ $ERRORS > '1' ]; then
			WORD='errors were'
		fi
		echo "$ERRORS $WORD reported.  Scroll up and look for the red."
	fi
}

multidev_merge() {
	## In this case, 'origin' is Pantheon remote name.  
    git clone $GITURL pantheon-clone_${SITENAME}
    cd pantheon-clone_${SITENAME}
    git fetch --all

    # check for errors
    if [ $? -ne 0 ]; then
	    echo "git fetch --all failed"
	    exit 1
    fi

	# merge back to pantheon
	git merge origin/$MDENV
	
	if [ $? -ne 0 ]; then
	    echo "Merge failed"
	    Timestamp = date +"%Y-%m-%d-%T"
	    git merge --abort 2> conflicts.${Timestamp}.txt 
	    git reset --hard origin/master
	    git clean -df
	    exit 1
	fi

	git push origin master
	printf "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\nMultidev pushed to master. Visit dev environment to view updates\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n\n"
}

multidev_deploy_to_test() {
	read -p "Deploy changes to test environment on Pantheon? MAKE SURE DEV IS SYNCHED FIRST [y/n] " DEPLOYTEST
	case $DEPLOYTEST in
		[Yy]* ) read -p "Please provide a note to attach to this deployment to Test: " MESSAGE
				terminus env:deploy --note="$MESSAGE" --cc --updatedb -- ${SITENAME}.test;;
		[Nn]* ) exit 0;;
	esac
}

multidev_deploy_to_live() {
	read -p "Deploy changes to live environment on Pantheon? MAKE SURE TEST IS SYNCHED FIRST [y/n] " DEPLOYLIVE
	case $DEPLOYLIVE in
		[Yy]* ) read -p "Please provide a note to attach to this deployment to Live: " MESSAGE
				terminus env:deploy --note="$MESSAGE" --cc --updatedb -- ${SITENAME}.live;;
		[Nn]* ) exit 0;;
	esac
}

multidev_finish() {
	SITE=$1
	MDENV='env-term'
	SITEINFO=`terminus site:info ${SITENAME} --field=id`
	SITEID=${SITEINFO#*: }
	GITURL="ssh://codeserver.dev.${SITEID}@codeserver.dev.${SITEID}.drush.in:2222/~/repository.git"

    read -p "Please provide git commit message: " MESSAGE
    terminus env:commit ${SITENAME}.${MDENV} --message="$MESSAGE" 
    terminus env:commit ${SITENAME}.${MDENV}

    # check for errors
    if [ $? -ne 0 ]; then
	    echo "git commit failed"
	    exit 1
    fi

    echo "Returning env-term to git connection-mode..."
    terminus connection:set ${SITENAME}.${MDENV} git
    if [ $? -ne 0 ]; then
	    echo "Switching connection mode back to git failed."
	    exit 1
    fi 
	
	# merge to git and make pantheon cycles
	multidev_merge
	multidev_deploy_to_test
	multidev_deploy_to_live


	# finish by deleting multidev
	read -p "Delete env-term multidev? [y/n]  " yn
	case $yn in
		[Yy]* ) terminus multidev:delete --delete-branch -- ${SITENAME}.${MDENV}
	esac

}


# check for logged in user
terminus_auth

# grab the sites
printf '\nLoading site list...\n'
terminus site:list --fields="name,framework,ID"

# set the site
read -p 'Type in site name and press [Enter] to start updating: ' SITENAME
STEP='start'
step_route

# final steps
read -p "Press [Enter] to finish updating ${SITENAME}" 
STEP='finish'
step_route

read -p 'Log out of Terminus? [y/n] ' LOGOUT
  case $LOGOUT in
        [Yy]* ) terminus auth:logout

  esac

read -p "Delete pantheon-clone folder? [y/n] " yn
  case $yn in
        [Yy]*) cd ..
               printf "deleting pantheon-clone...\n" 
               rm -rf pantheon-clone_${SITENAME};;
  esac

exit 0