# pantheon-site-update
Command line script to update Drupal sites on Pantheon. Will check for and apply upstream updates and module updates, then push up to dev, test, and live.

For Drupal 7 and below it will update the modules and database via drush. For Drupal 8 and above it will skip module updates in favor of composer based updates.

## Setup
Download or copy script and cd into directory with script.

Make script executable by running:

``chmod 755 pantheon-site-update.sh``

Then run the script:

``./pantheon-site-update.sh``

## Instructions
You can run the script without any arguments or flags and it will walk you through the steps with instructions and information.

Or pass the Pantheon sitename into the script and have it walk you through the update process:

``./pantheon-site-update.sh $SITENAME``

Or pass the --no-check flag to disable update prompts and pick your site from a list of sites in your account:

``./pantheon-site-update.sh --no-check``

Or pass the Pantheon sitename and the --no-check flag to disable update prompts and update the site passed:

``./pantheon-site-update.sh $SITENAME --no-check``


## Notes
If you pass the --no-check flag, then it will update dev, test, and live without asking you for confirmation. You also will not have the option to backup the live environment before updating.

If you do not pass the --no-check flag, then it will wait for your confirmation before pushing to test and live. You will have the option to backup the live environment before updating.

If you do not pass a sitename argument, then it will use terminus to gather a list of sites in your account.