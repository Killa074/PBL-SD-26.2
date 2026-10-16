/* ARMv7 Linux userspace MMIO accessors. r0=mapped register; r1=write value.
 * Device mapping supplied by mmap. Barriers order command-port/data writes.
 */
.syntax unified
.arch armv7-a
.text
.align 2
.global gpu_mmio_load32
.type gpu_mmio_load32, %function
gpu_mmio_load32:
    dmb sy
    ldr r0, [r0]
    dmb sy
    bx lr
.size gpu_mmio_load32, .-gpu_mmio_load32
.global gpu_mmio_store32
.type gpu_mmio_store32, %function
gpu_mmio_store32:
    dmb sy
    str r1, [r0]
    dmb sy
    bx lr
.size gpu_mmio_store32, .-gpu_mmio_store32
.section .note.GNU-stack,"",%progbits
