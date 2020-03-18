# pantheon-site-update
Command line script to update Drupal sites on Pantheon

## Setup
Download or copy script and cd into directory with script

Make script executable by running 

``bash
chmod 755 pantheon-site-update.sh
``

Then run the script

``bash
./pantheon-site-update.sh
``

Script will walk you through steps with instructions/information


## Workflow
The script does the following in order:
1. Checks if you are logged in via Terminus
1. Shows lists of sites under your account that are available
1. Option to backup live
1. Creates Multidev environment and pulls down DB from either dev/test/live
1. Checks for upstream updates and asks to apply to Multidev
1. Checks for Drupal modules updates and asks to apply to Multidev
1. **Pauses** and returns URL to Multidev for testing
1. Adds commit message and switches to git mode
1. Clones master repo from Pantheon into current working directory and cd into cloned directory
1. Fetch all tags 
1. Merges Multidev branch with origin **_THIS PUSHES CODE TO DEV ENVIRONMENT_**
1. **Pauses** and asks to deploy changes from dev->test **_MAKE SURE DEV HAS FINISHED SYNCHING BEFORE CONTINUING_**
1. Adds comit message and pushes to test
1. **Pauses** and asks to deploy changes from test->live **_MAKE SURE TEST HAS FINISHED SYNCHING BEFORE CONTINUING_**
1. Asks to delete Multidev environment
1. Asks to log out of Terminus
1. Asks to delete local cloned directory
1. Tah-dah your Drupal site has been updated with upstream and module updates!
