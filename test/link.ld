/* Linker script for powerpc-sail test programs.
 *
 * Bare-metal: no runtime, no stack setup beyond what a test does itself.
 * Code is placed at 0x0000_1000 — low memory is left free so that tests can
 * use it as scratch data with plain (rA|0)+d addressing — and the model
 * starts executing at the ELF entry point (_start) with address translation
 * off, so link addresses are physical addresses.
 */

OUTPUT_ARCH(powerpc)
ENTRY(_start)

SECTIONS
{
  . = 0x00001000;

  .text : { *(.text) *(.text.*) }
  .rodata : { *(.rodata) *(.rodata.*) }
  .data : { *(.data) *(.data.*) }
  .bss : { *(.bss) *(.bss.*) *(COMMON) }

  /DISCARD/ : { *(.comment) *(.note.*) *(.eh_frame*) }
}
