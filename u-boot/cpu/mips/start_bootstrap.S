#include <config.h>
#include <version.h>
#include <asm/regdef.h>
#include <asm/mipsregs.h>
#include <asm/addrspace.h>
#include <ar7240_soc.h>

#define Index_Load_Tag_D	0x05

	.macro	mips_cache_lock_24k
	.set push
	.set noreorder

	li      t0, 0x1f00
	li      t1, CFG_CACHELINE_SIZE
	li      t2, KSEG0
	addu    t3, t0, t2
	mtc0    zero, CP0_TAGLO

cache_loop_lock:
	li      t5, 0xfffff000
	and     t4, t2, t5
	ori     t4, t4, (1 << 7)
	mtc0    t4, CP0_TAGLO

	cache   Index_Load_Tag_D, 0(t2)
	cache   0x1d, 0(t2)
	addu    t2, t1
	bne     t2, t3, cache_loop_lock
	 nop

	.set	pop
	.endm

#define ATH_SPI_CLOCK	0x1F000004

#define RVECENT(f,n) \
   b f; nop

#define XVECENT(f,bev) \
   b f     ;           \
   li k0,bev

	.set noreorder

	.globl _start_bootstrap
	.text
_start_bootstrap:
	RVECENT(reset,0)	/* U-boot entry point */
	RVECENT(reset,1)	/* software reboot */

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

	/* CONFIG0 register */
	li	t0, CONF_CM_UNCACHED
	mtc0	t0, CP0_CONFIG


    /* Initialize GOT pointer.*/
	bal     1f
	nop
	.word   _GLOBAL_OFFSET_TABLE_
	1:
	move    gp, ra
	lw      t1, 0(ra)
	move	gp, t1

#if defined(CONFIG_MACH_HORNET) && defined(CONFIG_HORNET_1_1_WAR)
/**************************************************************************/
/*
 * WAR: Hornet 1.1 currently need a reset once we boot to let the resetb has
 *      enough time to stable, so that trigger reset at 1st boot, system team
 *      is investigaing the issue, will remove in short
 */

do_reset_normal:

    li  t7, 0xbd000000
    lw  t8, 0(t7)            // t8 : value of 0xbd000000
    li  t9, 0x12345678
    bne t8, t9, do_reset     // if value of 0xbd000000 != 0x12345678 , go to do_reset
    nop
    li  t9, 0xffffffff
    sw  t9, 0(t7)
    b   normal_path
    nop

do_reset:
    sw  t9, 0(t7)
    li  t7, 0xb806001c       // load reset register 0x1806001c
    lw  t8, 0(t7)
    li  t9, 0x1000000        // bit24, fullchip reset
    or  t8, t8, t9
    sw  t8, 0(t7)
do_reset_loop:
    b   do_reset_loop
    nop

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

#if defined(CONFIG_AR7100) || defined(CONFIG_AR7240)
	/* REMAP_DISABLE */
	// TODO: SPI clock from FLASH?
	// for now we will use divider = 10 ( (4+1)*2 )
	li	a0, KSEG1ADDR(ATH_SPI_CLOCK)
	li	t0, 0x44
	sw	t0, 0(a0)
#endif

	/* Initialize caches...
	 */
	la      t9, simple_mips_cache_reset
	jalr    t9
	nop

	/* ... and enable them.
	 */
	li	t0, CONF_CM_CACHABLE_NONCOHERENT
	mtc0	t0, CP0_CONFIG

	mips_cache_lock_24k

	li	t0, CFG_SDRAM_BASE + CFG_INIT_SP_OFFSET
	la	sp, 0(t0)

	la	t9, bootstrap_board_init_f
	j	t9
	nop

/*
 * void bootstrap_relocate_code (addr_sp, gd, addr_moni)
 *
 * This "function" does not return, instead it continues in RAM
 * after relocating the monitor code.
 *
 * a0 = addr_sp
 * a1 = gd
 * a2 = destination address
 */
	.globl	bootstrap_relocate_code
	.ent	bootstrap_relocate_code
bootstrap_relocate_code:
	move	sp, a0		/* Set new stack pointer		*/

	li	t0, BOOTSTRAP_CFG_MONITOR_BASE
	la	t3, in_ram
	lw	t2, -12(t3)	/* t2 <-- uboot_end_data_bootsrap	*/

	/*
	 * Ideally, following line is not needed. However,
	 * the behaviour is flaky without it. U-boot boots on
	 * some boards, and doesn't on some boards. Even on the
	 * boards it boots, it doesn't boot all the time.
	 *
	 * Adding 256k to what needs to be read in actually.
	 * This introduces some delay that seems to help boot.
	 */
	li	t3, (256 << 10)

	add	t2, t3
	move	t1, a2

	/*
	 * Fix GOT pointer:
	 *
	 * New GOT-PTR = (old GOT-PTR - BOOTSTRAP_CFG_MONITOR_BASE) + Destination Address
	 */
	move	t6, gp
	sub	gp, BOOTSTRAP_CFG_MONITOR_BASE
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
	addi	t0, a2, in_ram - _start_bootstrap
	j	t0
	nop

	.word	uboot_end_data_bootstrap
	.word	uboot_end_bootstrap
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
	lw	t1, -12(t0)	/* t1 <-- uboot_end_data_bootstrap	*/
	lw	t2, -8(t0)	/* t2 <-- uboot_end_bootstrap		*/
	add	t1, t6		/* adjust pointers		*/
	add	t2, t6

	sub	t1, 4
1:	addi	t1, 4
	bltl	t1, t2, 1b
	sw	zero, 0(t1)	/* delay slot			*/

	move	a0, a1
	la	t9, bootstrap_board_init_r
	j	t9
	move	a1, a2		/* delay slot			*/

	.end	bootstrap_relocate_code

	/* Exception handlers.
	 */
romReserved:
	b romReserved

romExcHandle:
	b romExcHandle
