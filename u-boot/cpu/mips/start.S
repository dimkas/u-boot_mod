#include <config.h>
#include <version.h>
#include <asm/regdef.h>
#include <asm/mipsregs.h>
#include <asm/addrspace.h>
#include <ar7240_soc.h>

#define ATH_SPI_CLOCK	0x1F000004

#define RVECENT(f,n) \
   b f; nop

#define XVECENT(f,bev) \
   b f     ;           \
   li k0,bev

	.set noreorder
#ifdef COMPRESSED_UBOOT
	.align 4
#endif
	.globl _start
	.text
_start:

#ifndef COMPRESSED_UBOOT
	RVECENT(reset,0)			/* U-boot entry point */
	RVECENT(reset,1)			/* software reboot */

	/* We hope there are no more reserved vectors!
	 * 128 * 8 == 1024 == 0x400
	 * so this is address R_VEC+0x400 == 0xbfc00400
	 */

	.align 4
reset:

	/*
	 * Clearing CP0 registers - This is generally required for the MIPS-24k
	 * core used by Atheros.
	 */
	mtc0	zero, $0
	mtc0	zero, $1
	mtc0	zero, $2
	mtc0	zero, $3
	mtc0	zero, $4
	mtc0	zero, $5
	mtc0	zero, $6
	mtc0	zero, $7
	mtc0	zero, $8
	mtc0	zero, $9
	mtc0	zero, $10
	mtc0	zero, $11
	li	t0, 0x10000004
	mtc0	t0, $12
	mtc0	zero, $13
	mtc0	zero, $14
	mtc0	zero, $15
	mtc0	zero, $16
	mtc0	zero, $17
	mtc0	zero, $18
	mtc0	zero, $19
	mtc0	zero, $20
	mtc0	zero, $21
	mtc0	zero, $22
	mtc0	zero, $23
	mtc0	zero, $24
	mtc0	zero, $25
	mtc0	zero, $26
	mtc0	zero, $27
	mtc0	zero, $28

	/*
	 * Clear watch registers.
	 */

	mtc0	zero, CP0_WATCHLO
	mtc0	zero, CP0_WATCHHI

	/* STATUS register */
	mfc0	k0, CP0_STATUS
	li	k1, ~ST0_IE
	and	k0, k1
        mtc0	zero, CP0_CAUSE
	mtc0	k0, CP0_STATUS

	/* CAUSE register */
	mtc0	zero, CP0_CAUSE

	/* Init Timer */
	mtc0	zero, CP0_COUNT
	mtc0	zero, CP0_COMPARE

#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	/* CONFIG0 register */
	li	t0, CONF_CM_UNCACHED
	mtc0	t0, CP0_CONFIG
#endif /* #ifndef CONFIG_SKIP_LOWLEVEL_INIT */

#endif /* #ifndef COMPRESSED_UBOOT */

    /* Initialize GOT pointer.*/
	bal     1f
	nop
	.word   _GLOBAL_OFFSET_TABLE_
	1:
	move    gp, ra
	lw      t1, 0(ra)
	move	gp, t1

#ifndef COMPRESSED_UBOOT

#if defined(CONFIG_MACH_HORNET) && defined(CONFIG_HORNET_1_1_WAR)
/**************************************************************************/
/*
 * WAR: Hornet 1.1 currently need a reset once we boot to let the resetb has
 *      enough time to stable, so that trigger reset at 1st boot, system team
 *      is investigaing the issue, will remove in short
 */

do_reset_normal:

    li  t7, 0xbd000000
    lw  t8, 0(t7)            // t8 : value of 0xb8050024
    li  t9, 0x12345678
    sw  t9, 0(t7)
    bne t8, t9, do_reset      // if 0xb8050024 == 0x19 , go to do_cpld
    nop
    b normal_path

do_reset:
    li t7, 0xb806001c       // load reset register 0x1806001c
    lw t8, 0(t7)
    li t9, 0x1000000        // bit24, fullchip reset
    or t8, t8, t9         // t8:  set bit 18
    sw t8, 0(t7)

normal_path:
#endif /* CONFIG_MACH_HORNET */

/**************************************************************************/

	/* Initialize any external memory.
	 */
	la      t9, hornet_pll_init
	jalr    t9
	nop
	nop

	la      t9, hornet_ddr_init
	jalr    t9
	nop
	nop

	la	t0, rel_start
	j	t0
	nop

rel_start:

#if defined(CONFIG_AR7100) || defined(CONFIG_AR7240) || defined(CONFIG_ATHEROS)
	/* REMAP_DISABLE */
	li	a0,	KSEG1ADDR(ATH_SPI_CLOCK)
	// TODO: SPI clock from FLASH?
	// for now we will use divider = 10 ( (4+1)*2 )
	li	t0,	0x44
	sw	t0,	0(a0)
#endif

#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	/* Initialize caches...
	 */
	la      t9, simple_mips_cache_reset
	jalr    t9
	nop

	/* ... and enable them.
	 */

1:	li	t0,	CONF_CM_CACHABLE_NONCOHERENT
2:	mtc0	t0,	CP0_CONFIG

#if defined(CONFIG_AR7100) || defined(CONFIG_AR7240)
    la      t9, mips_cache_lock_24k
    jalr    t9
    nop
#endif
#endif /* #ifndef CONFIG_SKIP_LOWLEVEL_INIT */

#endif /* #ifndef COMPRESSED_UBOOT */

	li	t0, CFG_SDRAM_BASE + CFG_INIT_SP_OFFSET
	la	sp, 0(t0)

	la	t9, board_init_f
	j	t9
	nop

/*
 * void relocate_code (addr_sp, gd, addr_moni)
 *
 * This "function" does not return, instead it continues in RAM
 * after relocating the monitor code.
 *
 * a0 = addr_sp
 * a1 = gd
 * a2 = destination address
 */
	.globl	relocate_code
	.ent	relocate_code
relocate_code:
	move	sp, a0		/* Set new stack pointer		*/

	li	t0, CFG_MONITOR_BASE
	la	t3, in_ram
	lw	t2, -12(t3)	/* t2 <-- uboot_end_data	*/
	move	t1, a2

	/*
	 * Fix GOT pointer:
	 *
	 * New GOT-PTR = (old GOT-PTR - CFG_MONITOR_BASE) + Destination Address
	 */
	move	t6, gp
	sub	gp, CFG_MONITOR_BASE
	add	gp, a2			/* gp now adjusted		*/
	sub	t6, gp, t6		/* t6 <-- relocation offset	*/

	/*
	 * t0 = source address
	 * t1 = target address
	 * t2 = source end address
	 */
1:
	lw	t3, 0(t0)
	sw	t3, 0(t1)
	addu	t0, 4
	ble	t0, t2, 1b
	addu	t1, 4			/* delay slot			*/

	/* If caches were enabled, we would have to flush them here.
	 */

	/* Jump to where we've relocated ourselves.
	 */
	addi	t0, a2, in_ram - _start
	j	t0
	nop

	.word	uboot_end_data
	.word	uboot_end
	.word	num_got_entries

in_ram:
	/* Now we want to update GOT.
	 */
	lw	t3, -4(t0)	/* t3 <-- num_got_entries	*/
	addi	t4, gp, 8	/* Skipping first two entries.	*/
	li	t2, 2
1:
	lw	t1, 0(t4)
	beqz	t1, 2f
	add	t1, t6
	sw	t1, 0(t4)
2:
	addi	t2, 1
	blt	t2, t3, 1b
	addi	t4, 4		/* delay slot			*/

	/* Clear BSS.
	 */
	lw	t1, -12(t0)	/* t1 <-- uboot_end_data	*/
	lw	t2, -8(t0)	/* t2 <-- uboot_end		*/
	add	t1, t6		/* adjust pointers		*/
	add	t2, t6

	sub	t1, 4
1:	addi	t1, 4
	bltl	t1, t2, 1b
	sw	zero, 0(t1)	/* delay slot			*/

	move	a0, a1
	la	t9, board_init_r
	j	t9
	move	a1, a2		/* delay slot			*/

	.end	relocate_code

#ifndef COMPRESSED_UBOOT
	/* Exception handlers */
romReserved:
	b romReserved

romExcHandle:
	b romExcHandle
#endif /* #ifndef COMPRESSED_UBOOT */
