/* 
 * strap.c
 * Created: Wed Dec 21 19:38:52 2016 by tek@wiw.org
 * Revised: Mon Jul  3 20:40:02 2000 by tek@wiw.org
 * Copyright 2016 Julian E. C. Squires (tek@wiw.org)
 * This program comes with ABSOLUTELY NO WARRANTY.
 * $Id$
 *
 * FIXME: This code currently must be compiled as a module.
 */

#include <linux/types.h>
#include <linux/fs.h>
#include <linux/module.h>
#include <linux/stat.h>
#include <linux/mm.h>

#include <asm/uaccess.h>
#include <asm/pgtable.h>
#include <asm/system.h>
#include <asm/io.h>
#include <asm/ldt.h>
#include <asm/processor.h>
#include <asm/desc.h>
#include <asm/mmu_context.h>

#define STRAP_NAME "strap"
#define STRAP_MAJOR 60
#define STRAP_MINOR 0
#define STRAP_BASE (0x1000)
#define STRAP_CODELEN (1024)

static unsigned char strap_code[STRAP_CODELEN];
static int strap_codepos = 0;

/* This stuff was taken from arch/i386/kernel/process.c in 2.3.99pre9, and
    modified for our purposes */

static unsigned long long real_mode_gdt_entries [] =
{
    0x0000000000000000ULL,  /* Null descriptor */
    0x00009a000000ffffULL,  /* 16-bit real-mode 64k code at 0x00000000 */
    0x000092000100ffffULL   /* 16-bit real-mode 64k data at 0x00000100 */
};

struct descriptortable_t
{
    unsigned short       size __attribute__ ((packed));
    unsigned long long * base __attribute__ ((packed));
};

/* See modeswitch.s */

static unsigned char mode_switch [] =
{
  0x66, 0x0f, 0x20, 0xC0,
  0x66, 0x66, 0x25, 0x11, 0x00, 0x00, 0x00,
  0x66, 0x66, 0x0D, 0x00, 0x00, 0x00, 0x60,
  0x66, 0x0F, 0x22, 0xC0,
  0x66, 0x66, 0x31, 0xDB,
  0x66, 0x0F, 0x22, 0xDB,
  0x66, 0x0F, 0x20, 0xC3,
  0x66, 0x66, 0x81, 0xE3, 0x00, 0x00, 0x00, 0x60,
  0x74, 0x02,
  0x0F, 0x09,
  0x24, 0x10,
  0x66, 0x0F, 0x22, 0xC0,
  0xEA, (unsigned char)(STRAP_BASE-STRAP_CODELEN), (unsigned char)((STRAP_BASE-STRAP_CODELEN)>>8),
  0x00, 0x00,			/*    jmp STRAP_BASE-STRAP_CODELEN        */
  /* Note on above magic number: this is where we always copy
     the code in our_machine_real_restart - this is very important! */
};


/*
 * UGLY - but required -- we aren't linking against the C library,
 *                        _AND_ we can't guarantee the kernel exports
 *                        __memcpy/__constant_memcpy
 */
void *our_memcpy(void *dest, void *src, size_t n)
{
    int i;

    for(i = 0; i < n; i++) *((char *)dest+i) = *((char *)src+i);

    return dest;
}

/*
 * Switch to real mode and then execute the code
 * specified by the code and length parameters.
 * We assume that length will always be less than STRAP_CODELEN
 */
void our_machine_real_restart(unsigned char *code, int length)
{
    struct descriptortable_t real_mode_gdt, real_mode_idt;

    real_mode_gdt.size = sizeof(real_mode_gdt_entries)-1;
    real_mode_gdt.base = real_mode_gdt_entries;
    real_mode_idt.size = 0x3ff;
    real_mode_idt.base = 0;

    cli();

    /* Remap the kernel at virtual address zero, as well as offset zero
       from the kernel segment.  This assumes the kernel segment starts at
       virtual address PAGE_OFFSET. */

    our_memcpy (swapper_pg_dir, swapper_pg_dir + USER_PGD_PTRS,
		sizeof (swapper_pg_dir [0]) * KERNEL_PGD_PTRS);

    /* Make sure the first page is mapped to the start of physical memory.
       It is normally not mapped, to trap kernel NULL pointer dereferences. */

    pg0[0] = _PAGE_RW | _PAGE_PRESENT;

    /*
     * Use `swapper_pg_dir' as our page directory.
     */
    asm volatile("movl %0,%%cr3": :"r" (__pa(swapper_pg_dir)));

    /* For the switch to real mode, copy some code to low memory.  It has
       to be in the first 64k because it is running in 16-bit mode, and it
       has to have the same physical and virtual address, because it turns
       off paging.  Copy it near the end of the first page, out of the way
       of BIOS variables. */

    our_memcpy ((void *) (STRAP_BASE - (sizeof (mode_switch) + STRAP_CODELEN)),
		mode_switch, sizeof (mode_switch));
    our_memcpy ((void *) (STRAP_BASE - STRAP_CODELEN), code, length);

    /* Set up the IDT for real mode. */

    __asm__ __volatile__ ("lidt %0" : : "m" (real_mode_idt));

    /* Set up a GDT from which we can load segment descriptors for real
       mode.  The GDT is not used in real mode; it is just needed here to
       prepare the descriptors. */

    __asm__ __volatile__ ("lgdt %0" : : "m" (real_mode_gdt));

    /* Load the data segment registers, and thus the descriptors ready for
       real mode.  The base address of each segment is 0x100, 16 times the
       selector value being loaded here.  This is so that the segment
       registers don't have to be reloaded after switching to real mode:
       the values are consistent for real mode operation already. */

    __asm__ __volatile__ ("movl $0x0010,%%eax\n"
                          "\tmovl %%eax,%%ds\n"
                          "\tmovl %%eax,%%es\n"
                          "\tmovl %%eax,%%fs\n"
                          "\tmovl %%eax,%%gs\n"
                          "\tmovl %%eax,%%ss" : : : "eax");

    /* Jump to the 16-bit code that we copied earlier.  It disables paging
       and the cache, switches to real mode, and jumps to the BIOS reset
       entry point. */

    __asm__ __volatile__ ("ljmp $0x0008,%0"
                          :
                          : "i" ((void *) (STRAP_BASE - sizeof(mode_switch) - STRAP_CODELEN)));
}

static ssize_t strap_write(struct file *file, const char *buf, size_t count,
                           loff_t *ppos)
{
    if(strap_codepos+count < STRAP_CODELEN)
        our_memcpy(strap_code+strap_codepos, (char *)buf, count);
    else
        our_memcpy(strap_code+strap_codepos, (char *)buf,
		   STRAP_CODELEN-strap_codepos);
    strap_codepos += count;

    if(strap_codepos >= STRAP_CODELEN)
        our_machine_real_restart(strap_code, STRAP_CODELEN);

    return count; /* we're so lazy - doesn't matter, though, because
                   * userland never gets to see the return if we didn't
                   * write the full buffer */
}

/* FIXME: Perhaps we want to provide nops for the other operations? */
static struct file_operations strap_fops = {
    write:		strap_write
};

int init_module(void)
{
    int i;

    /* register major 60 minor 0 */
    if(i=register_chrdev(STRAP_MAJOR, STRAP_NAME, &strap_fops) != 0) {
        printk(KERN_ERR "strap: failed even the oldschool way, major must " \
               "be taken\n");
        return i;
    }
    printk(KERN_INFO "strap: loaded /dev/strap support\n");

    return 0;
}

void cleanup_module(void)
{
    /* unregister major 60 minor 0 */
    unregister_chrdev(STRAP_MAJOR, STRAP_NAME);
}

/* EOF strap.c */
