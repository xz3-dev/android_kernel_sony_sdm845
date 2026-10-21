/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Call sites for KernelSU-Next in manual hook mode (CONFIG_KSU_MANUAL_HOOK).
 * The handlers live in drivers/kernelsu; without manual hooks they compile
 * to nothing.
 */
#ifndef _LINUX_KSU_HOOK_H
#define _LINUX_KSU_HOOK_H

#include <linux/compiler.h>
#include <linux/types.h>

struct filename;
struct stat;
struct stat64;

#ifdef CONFIG_KSU_MANUAL_HOOK
extern bool ksu_init_rc_hook;
extern bool ksu_input_hook;

int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,
			void *envp, int *flags);
int ksu_handle_faccessat(int *dfd, const char __user **filename_user,
			 int *mode, int *flags);
int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
void ksu_handle_sys_read(unsigned int fd);
void ksu_handle_newfstat_ret(unsigned int *fd,
			     struct stat __user **statbuf_ptr);
void ksu_handle_fstat64_ret(unsigned long *fd,
			    struct stat64 __user **statbuf_ptr);
int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code,
				  int *value);
int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,
			  void __user **arg);

static inline void ksu_hook_sys_read(unsigned int fd)
{
	if (unlikely(READ_ONCE(ksu_init_rc_hook)))
		ksu_handle_sys_read(fd);
}

static inline void ksu_hook_input_event(unsigned int *type,
					unsigned int *code, int *value)
{
	if (unlikely(READ_ONCE(ksu_input_hook)))
		ksu_handle_input_handle_event(type, code, value);
}
#else
static inline int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
				      void *argv, void *envp, int *flags)
{
	return 0;
}

static inline int ksu_handle_faccessat(int *dfd,
				       const char __user **filename_user,
				       int *mode, int *flags)
{
	return 0;
}

static inline int ksu_handle_stat(int *dfd, const char __user **filename_user,
				  int *flags)
{
	return 0;
}

static inline void ksu_handle_newfstat_ret(unsigned int *fd,
					   struct stat __user **statbuf_ptr)
{
}

static inline void ksu_handle_fstat64_ret(unsigned long *fd,
					  struct stat64 __user **statbuf_ptr)
{
}

static inline int ksu_handle_sys_reboot(int magic1, int magic2,
					unsigned int cmd, void __user **arg)
{
	return 0;
}

static inline void ksu_hook_sys_read(unsigned int fd)
{
}

static inline void ksu_hook_input_event(unsigned int *type,
					unsigned int *code, int *value)
{
}
#endif /* CONFIG_KSU_MANUAL_HOOK */

#endif /* _LINUX_KSU_HOOK_H */
