AUTOMAKE_OPTIONS = 1.6 foreign

SUBDIRS = cg roa-lib proto roa-utils rsync_aur testcases server

ACLOCAL_AMFLAGS = -I build-aux

test: all
	cd testcases && ./makeall
	cd subsystemTests && ./runSubsystemTest.sh 1 9
	cd subsystemTests && ./runSubsystemTest.sh 2 8
	cd subsystemTests && ./runSubsystemTest.sh 3 9
	@echo '**** All RPKI Subsystem tests ran successfully. ****'