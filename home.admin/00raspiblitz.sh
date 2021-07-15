#!/bin/bash

#######################################
# SSH USER INTERFACE
# gets called when user logins per SSH
# or calls 'raspiblitz' on the terminal
#######################################
echo "Starting SSH user interface ... (please wait)"

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# check if raspiblitz.info exists
systemInfoExists=$(ls ${infoFile} | grep -c "${infoFile}")
if [ "${systemInfoExists}" != "1" ]; then
  echo "systemInfoExists(${systemInfoExists})"
  echo "FAIL: ${infoFile} does not exist .. which it should at this point."
  echo "Check logs & bootstrap.service for errors and report to devs."
  exit 1
fi

# get system state information raspiblitz.info
source ${infoFile}

# check that basic system phase/state information is available
if [ "${setupPhase}" == "" ] || [ "${state}" == "" ]; then
  echo "setupPhase(${setupPhase}) state(${state})"
  echo "FAIL: ${infoFile} does not exist or missing state."
  echo "Check logs & bootstrap.service for errors and report to devs."
  exit 1
fi

# special state: copysource
if [ "${state}" = "copysource" ]; then
  echo "***********************************************************"
  echo "INFO: You lost connection during copying the blockchain"
  echo "You have the following options:"
  echo "a) continue/check progress with command: sourcemode"
  echo "b) return to normal mode with command: restart"
  echo "***********************************************************"
  exit
fi

# special state: copytarget
source <(/home/admin/config.scripts/blitz.copychain.sh status)
if [ "${copyInProgress}" = "1" ]; then
  echo "Detected interrupted COPY blochain process ..."
  /home/admin/config.scripts/blitz.copychain.sh target
  exit
fi

# special state: reindex was triggered
if [ "${state}" = "reindex" ]; then
  echo "Re-Index in progress ... start monitoring:"
  /home/admin/config.scripts/network.reindex.sh
  exit
fi

# special state: copystation
if [ "${state}" = "copystation" ]; then
  echo "Copy Station is Runnning ..."
  echo "reboot to return to normal"
  sudo /home/admin/XXcopyStation.sh
  exit
fi

# prepare status file
# TODO: this is to be replaced and unified together with raspiblitz.info
# when we move to a background monitoring thread & redis for WebUI with v1.8
sudo touch /var/cache/raspiblitz/raspiblitz.status
sudo chown admin:admin /var/cache/raspiblitz/raspiblitz.status
sudo chmod 740 /var/cache/raspiblitz/raspiblitz.status

#####################################
# SSH MENU LOOP
# this loop runs until user exits or
# an error drops user to terminal
#####################################

exitMenuLoop=0
doneIBD=0
while [ ${exitMenuLoop} -eq 0 ]
do

  #####################################
  # Access fresh system info on every loop

  # refresh system state information
  source ${infoFile}

  # gather fresh status scan and store results in memory
  # TODO: move this into background loop and unify with redis data storage later
  sudo /home/admin/config.scripts/blitz.statusscan.sh > /var/cache/raspiblitz/raspiblitz.status
  source /var/cache/raspiblitz/raspiblitz.status

  #####################################
  # ALWAYS: Handle System States 
  #####################################

  ############################
  # LND Wallet Unlock

  if [ "${walletLocked}" == "1" ] && [ "${state}" == "ready" ]; then
    /home/admin/config.scripts/lnd.unlock.sh
  fi

  #####################################
  # SETUP MENU
  #####################################

  # when is needed & bootstrap process signals that it waits for user dialog 
  if [ "${setupPhase}" != "done" ] && [ "${state}" == "waitsetup" ]; then
    # push user to main menu
    /home/admin/setup.scripts/controlSetupDialog.sh
    # use the exit code from setup menu as signal if menu loop should exited
    # 0 = continue loop / everything else = break loop and exit to terminal
    exitMenuLoop=$?
    if [ "${exitMenuLoop}" != "0" ]; then break; fi
  fi

  #####################################
  # SETUP DONE DIALOGS
  #####################################

  # when is needed & bootstrap process signals that it waits for user dialog 
  if [ "${setupPhase}" != "done" ] && [ "${state}" == "waitfinal" ]; then
    # push to final setup gui dialogs
    /home/admin/setup.scripts/controlFinalDialog.sh
    continue
  fi  

  #####################################
  # INITIAL BLOCKCHAIN SYNC (SUBLOOP)
  #####################################
  if [ "${setupPhase}" == "done" ] && [ "${state}" == "ready" ] && [ "${initialSync}" == "1" ]; then
    echo "debug wait eventBlockchainSync.sh ..."
    sleep 3
    /home/admin/setup.scripts/eventBlockchainSync.sh ssh loop
    continue
  fi

  #####################################
  # MAIN MENU or BLOCKCHAIN SYNC
  #####################################

  # when setup is done & state is ready .. jump to main menu
  if [ "${setupPhase}" == "done" ] && [ "${state}" == "ready" ]; then
    # MAIN MENU
    /home/admin/00mainMenu.sh
    # use the exit code from main menu as signal if menu loop should exited
    # 0 = continue loop / everything else = break loop and exit to terminal
    exitMenuLoop=$?
    if [ "${exitMenuLoop}" != "0" ]; then break; fi
  fi

  #####################################
  # DURING SETUP: Handle System States 
  #####################################

  if [ "${setupPhase}" != "done" ]; then

    #echo "# DURING SETUP: Handle System State (${state})"

    # when no HDD on Vagrant - just print info & exit (admin info & exit)
    if [ "${state}" == "noHDD" ] && [ ${vagrant} -gt 0 ]; then
      echo "***********************************************************"
      echo "VAGRANT INFO"
      echo "***********************************************************"
      echo "To connect a HDD data disk to your VagrantVM:"
      echo "- shutdown VM with command: off"
      echo "- open your VirtualBox GUI and select RaspiBlitzVM"
      echo "- change the 'mass storage' settings"
      echo "- add a second 'Primary Slave' drive to the already existing controller"
      echo "- close VirtualBox GUI and run: vagrant up & vagrant ssh"
      echo "***********************************************************"
      echo "You can either create a new dynamic VDI with around 900GB or download"
      echo "a VDI with a presynced blockchain to speed up setup. If you dont have 900GB"
      echo "space on your laptop you can store the VDI file on an external drive."
      echo "***********************************************************"
      exit 1
    fi

    # for all critical errors (admin info & exit)
    if [ "${state}" == "errorHDD" ]; then
      echo "***********************************************************"
      echo "SETUP ERROR - please report to development team"
      echo "***********************************************************"
      echo "state(${state}) message(${message})"
      if [ "${state}" == "errorHDD" ]; then
        # print some debug detail info on HDD/SSD error
        sudo /home/admin/config.scripts/blitz.datadrive.sh status
      fi
      echo "command to shutdown --> off"
      exit 1
    else
        # every other state just push as event to SSH frontend
        echo "debug wait eventInfoWait.sh ..."
        sleep 3
        /home/admin/setup.scripts/eventInfoWait.sh "${state}" "${message}"
    fi

  fi

done

echo "# menu loop received exit code ${exitMenuLoop} --> exit to terminal"
echo "***********************************"
echo "* RaspiBlitz Commandline"
echo "* Here be dragons .. have fun :)"
echo "***********************************"
if [ "${setupPhase}" == "done" ]; then
  echo "Bitcoin command line options: bitcoin-cli help"
  echo "LND command line options: lncli -h"
else
  echo "Your setup is not finished."
  echo "For setup logs: cat raspiblitz.log"
  echo "or call the command 'debug' to see bigger report."
fi
echo "Back to menus use command: raspiblitz"
echo
exit 0
