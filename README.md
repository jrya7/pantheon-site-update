# pantheon-site-update
Command line script to update Drupal sites on Pantheon. Will check for and apply upstream updates and module updates, then push up to dev, test, and live allowing time to test before pushing to the next environment.

## Setup
Download or copy script and cd into directory with script

Make script executable by running 

``chmod 755 pantheon-site-update.sh``

Then run the script

``./pantheon-site-update.sh``

Script will walk you through steps with instructions and information

Or pass the Pantheon sitename into the script

``./pantheon-site-update.sh $SITENAME``


## Workflow
The script does the following in order:
1. Checks if you are logged in via Terminus
1. Shows lists of sites under your account that are available
1. Option to backup live first
1. Checks for upstream updates and asks to apply to dev environment
1. Checks for Drupal modules updates and asks to apply to dev environment
1. Returns URL to dev environment for testing
1. Adds comit message and pushes to test
1. Adds comit message and pushes to live


Tah-dah your Drupal site has been updated with upstream and module updates!
