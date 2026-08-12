#import "internal.h"
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <errno.h>
#import <sys/mount.h>

SInt32 CFUserNotificationDisplayAlert(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL, CFURLRef soundURL, CFURLRef localizationURL, CFStringRef alertHeader, CFStringRef alertMessage, CFStringRef defaultButtonTitle, CFStringRef alternateButtonTitle, CFStringRef otherButtonTitle, CFOptionFlags *responseFlags) API_AVAILABLE(ios(3.0));

/*
void execute_unsandboxed(void (^block)(void))
{
	uint64_t credBackup = 0;
	jbclient_root_steal_ucred(0, &credBackup);
	block();
	jbclient_root_steal_ucred(credBackup, NULL);
}

int mount_unsandboxed(const char *type, const char *dir, int flags, void *data)
{
	__block int r = 0;
	execute_unsandboxed(^{
		r = mount(type, dir, flags, data);
	});
	return r;
}

int unmount_unsandboxed(const char *dir, int flags)
{
	__block int r = 0;
	execute_unsandboxed(^{
		r = unmount(dir, flags);
	});
	return r;
}

bool is_protected(const char *path)
{
	struct statfs sb;
	statfs(path, &sb);
	return strcmp(path, sb.f_mntonname) == 0;
}

int ensure_protected(const char *path)
{
	if (!is_protected(path)) {
		return mount_unsandboxed("bindfs", path, 0, (void *)path);
	}
	return 0;
}

int ensure_unprotected(const char *path)
{
	if (is_protected(path)) {
		return unmount_unsandboxed(path, MNT_FORCE);
	}
	return 0;
}

int protection_set_active(bool active)
{
	int r = 0;
	if (active) {
		// Protect /private/preboot/UUID/<System, usr> from being modified by bind mounting them on top of themselves
		// This protects dumb users from accidentally deleting these, which would induce a recovery loop after rebooting
		r |= ensure_protected(prebootUUIDPath("/System"));
		r |= ensure_protected(prebootUUIDPath("/usr"));
	}
	else {
		r |= ensure_unprotected(prebootUUIDPath("/System"));
		r |= ensure_unprotected(prebootUUIDPath("/usr"));
	}
	return r;
}

bool fakelib_is_mounted(void)
{
	struct statfs fsb;
    if (statfs("/usr/lib", &fsb) != 0) return NO;
    return strcmp(fsb.f_mntonname, "/usr/lib") == 0;
}

int fakelib_set_mounted(bool mounted)
{
	int r = 0;
	if (mounted != fakelib_is_mounted()) {
		if (mounted) {
			r = mount_unsandboxed("bindfs", "/usr/lib", MNT_RDONLY, (void *)JBROOT_PATH("/basebin/.fakelib"));
		}
		else {
			r = unmount_unsandboxed("/usr/lib", MNT_FORCE);
		}
	}
	return r;
}
*/

static NSString *fontMountSnapshotPath(void)
{
	return [JBROOT_PATH(@"/mnt") stringByAppendingString:@"/System/Library/Fonts"];
}

static int ensureFontMountSnapshot(void)
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *sourcePath = @"/System/Library/Fonts";
	NSString *snapshotPath = fontMountSnapshotPath();
	BOOL isDirectory = NO;

	if (![fileManager fileExistsAtPath:sourcePath isDirectory:&isDirectory] || !isDirectory) {
		fprintf(stderr, "FontMount: source directory is unavailable\n");
		return ENOENT;
	}

	if ([fileManager fileExistsAtPath:snapshotPath isDirectory:&isDirectory] && isDirectory) {
		NSArray *contents = [fileManager contentsOfDirectoryAtPath:snapshotPath error:nil];
		if (contents.count > 0) return 0;
		[fileManager removeItemAtPath:snapshotPath error:nil];
	}

	NSString *parentPath = [snapshotPath stringByDeletingLastPathComponent];
	NSError *error = nil;
	if (![fileManager createDirectoryAtPath:parentPath withIntermediateDirectories:YES attributes:nil error:&error]) {
		fprintf(stderr, "FontMount: cannot create snapshot parent: %s\n", error.localizedDescription.UTF8String);
		return EIO;
	}

	NSString *temporaryPath = [snapshotPath stringByAppendingFormat:@".creating-%@", NSUUID.UUID.UUIDString];
	[fileManager removeItemAtPath:temporaryPath error:nil];
	if (![fileManager copyItemAtPath:sourcePath toPath:temporaryPath error:&error]) {
		fprintf(stderr, "FontMount: snapshot copy failed: %s\n", error.localizedDescription.UTF8String);
		[fileManager removeItemAtPath:temporaryPath error:nil];
		return EIO;
	}

	NSArray *copiedContents = [fileManager contentsOfDirectoryAtPath:temporaryPath error:&error];
	if (!copiedContents || copiedContents.count == 0) {
		fprintf(stderr, "FontMount: copied snapshot is empty\n");
		[fileManager removeItemAtPath:temporaryPath error:nil];
		return EIO;
	}

	[fileManager removeItemAtPath:snapshotPath error:nil];
	if (![fileManager moveItemAtPath:temporaryPath toPath:snapshotPath error:&error]) {
		fprintf(stderr, "FontMount: cannot publish snapshot: %s\n", error.localizedDescription.UTF8String);
		[fileManager removeItemAtPath:temporaryPath error:nil];
		return EIO;
	}

	return 0;
}

int jbctl_handle_internal(const char *command, int argc, char* argv[])
{
	if (!strcmp(command, "launchd_stash_port")) {
		mach_port_t *selfInitPorts = NULL;
		mach_msg_type_number_t selfInitPortsCount = 0;
		if (mach_ports_lookup(mach_task_self(), &selfInitPorts, &selfInitPortsCount) != 0) {
			printf("ERROR: Failed port lookup on self\n");
			return -1;
		}
		if (selfInitPortsCount < 3) {
			printf("ERROR: Unexpected initports count on self\n");
			return -1;
		}
		if (selfInitPorts[2] == MACH_PORT_NULL) {
			printf("ERROR: Port to stash not set\n");
			return -1;
		}

		printf("Port to stash: %u\n", selfInitPorts[2]);

		mach_port_t launchdTaskPort;
		if (task_for_pid(mach_task_self(), 1, &launchdTaskPort) != 0) {
			printf("task_for_pid on launchd failed\n");
			return -1;
		}
		mach_port_t *launchdInitPorts = NULL;
		mach_msg_type_number_t launchdInitPortsCount = 0;
		if (mach_ports_lookup(launchdTaskPort, &launchdInitPorts, &launchdInitPortsCount) != 0) {
			printf("mach_ports_lookup on launchd failed\n");
			return -1;
		}
		if (launchdInitPortsCount < 3) {
			printf("ERROR: Unexpected initports count on launchd\n");
			return -1;
		}
		launchdInitPorts[2] = selfInitPorts[2]; // Transfer port to launchd
		if (mach_ports_register(launchdTaskPort, launchdInitPorts, launchdInitPortsCount) != 0) {
			printf("ERROR: Failed stashing port into launchd\n");
			return -1;
		}
		mach_port_deallocate(mach_task_self(), launchdTaskPort);
		return 0;
	}
/*
	else if (!strcmp(command, "protection")) {
		bool toSet = false;
		if (argc > 1) {
			if (!strcmp(argv[1], "activate")) {
				toSet = true;
			}
			else if (!strcmp(argv[1], "deactivate")) {
				toSet = false;
			}
			else {
				return -1;
			}

			return protection_set_active(toSet);
		}
		return -1;
	}
	else if (!strcmp(command, "fakelib")) {
		bool toMount = false;
		if (argc > 1) {
			if (!strcmp(argv[1], "mount")) {
				toMount = true;
			}
			else if (!strcmp(argv[1], "unmount")) {
				toMount = false;
			}
			else {
				return -1;
			}

			return fakelib_set_mounted(toMount);
		}
		return -1;
	}
*/
	else if (!strcmp(command, "startup")) {
//		protection_set_active(true);

JBLogDebug("jbctl startup: checking userspace panic ...");

		char *panicMessage = NULL;
		if (jbclient_watchdog_get_last_userspace_panic(&panicMessage) == 0) {
			NSString *printMessage = [NSString stringWithFormat:@"Dopamine has protected you from a userspace panic by temporarily disabling tweak injection and triggering a userspace reboot instead. A log is available under Analytics in the Preferences app. You can reenable tweak injection in the Dopamine app.\n\nPanic message: \n%s", panicMessage];
			CFUserNotificationDisplayAlert(0, 2/*kCFUserNotificationCautionAlertLevel*/, NULL, NULL, NULL, CFSTR("Watchdog Timeout"), (__bridge CFStringRef)printMessage, NULL, NULL, NULL, NULL);
			free(panicMessage);
		}


/************************* roothide specific ***************************/
//only bootstrap after launchdhook and systemhook available
JBLogDebug("jbctl startup: bootstrapping launch daemons ...");
exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "bootstrap", "system", "/Library/LaunchDaemons", NULL);

JBLogDebug("jbctl startup: refreshing jailbroken apps ...");
/************************* roothide specific ***************************/


		exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-a", NULL);
	}
	else if (!strcmp(command, "install_pkg")) {
		if (argc > 1) {
			extern char **environ;
			const char *dpkg = JBROOT_PATH("/usr/bin/dpkg");
			int r = execve(dpkg, (char *const *)(const char *[]){dpkg, "-i", argv[1], NULL}, environ);
			return r;
		}
		return -1;
	}
	else if (!strcmp(command, "font_mount")) {
		uint64_t originalUcred = 0;
		int result = EPERM;
		if (jbclient_root_steal_ucred(0, &originalUcred) == 0) {
			result = ensureFontMountSnapshot();
			if (result == 0) {
				result = mount("bindfs", "/System/Library/Fonts", MNT_RDONLY,
					(void *)fontMountSnapshotPath().fileSystemRepresentation);
				if (result != 0) result = errno;
			}
			jbclient_root_steal_ucred(originalUcred, NULL);
		}
		return result;
	}
	else if (!strcmp(command, "font_unmount")) {
		uint64_t originalUcred = 0;
		int result = EPERM;
		if (jbclient_root_steal_ucred(0, &originalUcred) == 0) {
			result = unmount("/System/Library/Fonts", MNT_FORCE);
			if (result != 0) result = errno;
			jbclient_root_steal_ucred(originalUcred, NULL);
		}
		return result;
	}
	return -1;
}
