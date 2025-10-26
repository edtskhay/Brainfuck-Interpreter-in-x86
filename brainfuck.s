.global brainfuck

format_str: 	.asciz 	"We should be executing the following code:\n%s"

tape_size: 		.quad 	1048576 # 1 MiB

i_ptr_right:	.byte 	62	# > move the pointer right
i_ptr_left: 	.byte	60 	# < move the pointer left
i_cell_inc: 	.byte	43	# + increment the current cell
i_cell_dec: 	.byte	45	# - decrement the current cell
i_out_cell: 	.byte	46	# . output the value of the current cell
i_in_cell: 		.byte	44	# , replace the value of the current cell with input
i_jz: 			.byte	91 # [ jump to the matching ] instruction if the current value is zero
i_jnz:			.byte   93 # ] jump to the matching [ instruction if the current value is not zero

jmptable_0:			
	.quad 	cmd_cell_inc
	.quad	cmd_in_cell
	.quad	cmd_cell_dec
	.quad	cmd_out_cell	

# Your brainfuck subroutine will receive one argument:
# a zero termianted string containing the code to execute.
brainfuck:
	pushq 	%rbp
	movq 	%rsp, %rbp

	pushq	%r15
	pushq	%r14
	pushq	%r13
	pushq	%r12
	pushq	%rbx
	subq	$8, %rsp	# align for calloc

#	%r12 -> program counter
#	%r13 -> cell pointer
#	%bl  -> current instruction
#	%r14 -> match jump counter (open is add 1, close is subtract 1)
#	%r15 -> calloc memory

	movq	%rdi, %r12				# set program counter to the start of the string

# allocate tape memory, and initialise to 0
	movq 	tape_size, %rdi
	movq 	$1, %rsi
	call 	calloc

	movq 	%rax, %r13				# store the allocated memory address
	movq 	%rax, %r15
	xor		%r14, %r14				# clear matching jump counter
#	stack stores loop jump locations

# now we start interpreting
	interpret_start:
		movzbq	(%r12), %rbx
		cmpb	$0, %bl
		jz		interpret_end		# check if we reached end of null terminated string

		cmpq	$0, %r14
		ja		check_close_loop_cmd# if the nested loop count register is > zero, loop until that matching pop is found

		subb	$43, %bl
		cmpb	$3, %bl				# range is [43, 46] - 43 = [0, 3] for 4 instructions, compute jump table
		ja		check_other_cmd

		shlb	$3, %bl 			# compute jump table offsets
		movq 	jmptable_0(%rbx), %rbx
		jmpq	*%rbx
		
		cmd_cell_inc: 
			incb	(%r13)			# increment value of the current cell
			incq	%r12
			jmp		interpret_start
		cmd_cell_dec: 
			decb	(%r13)			# decrement value of the current cell
			incq	%r12
			jmp		interpret_start
		cmd_out_cell: 
			call 	fast_print_char	# output single character
			incq	%r12
			jmp		interpret_start
		cmd_in_cell: 
			call 	getchar			# read single character
			movb  	%al, (%r13)
			incq	%r12
			jmp		interpret_start
	check_other_cmd:
		addb	$43, %bl

# check for <>[] instructions
		cmpb	i_ptr_right, %bl
		je		cmd_ptr_inc			

		cmpb	i_ptr_left, %bl
		je		cmd_ptr_dec

		cmpb	i_jz, %bl
		je		cmd_jz

		cmpb	i_jnz, %bl
		je		cmd_jnz

		incq	%r12
		jmp		interpret_start 	# invalid char

		cmd_ptr_inc: 
			incq	%r13			# shift pointer to the right
			incq	%r12
			jmp		interpret_start
		cmd_ptr_dec: 
			decq	%r13			# shift pointer to the left
			incq	%r12
			jmp		interpret_start
		cmd_jz: 
			pushq	%r12			# save program counter
			cmpb	$0, (%r13)		# check if zero, if it's zero, skip to the matching ]
			jnz		cmd_jz_false	
			cmd_jz_true:
				incq	%r14		# increment the nested loop counter
			cmd_jz_false:
				incq	%r12		
				jmp		interpret_start
		cmd_jnz: 
			popq	%r8				# pop matching [ jmp address
			cmpb	$0, (%r13)		# if zero, don't return to matching [
			jz		cmd_jnz_false 	
			cmd_jnz_true:
				movq	%r8, %r12
				pushq	%r12 			# re-push the start loop so we can jump back to it in the future
				incq	%r12 			# start executing the instruction immediately after
				jmp		interpret_start
			cmd_jnz_false:
				incq	%r12
				jmp		interpret_start

		check_close_loop_cmd: 			# if [ condition is true, skip to end bracket, this checks for THAT ] bracket
			cmpb	i_jz, %bl
			je		not_close_counter 	# if [ bracket, no need to jmp to anything
			cmpb	i_jnz, %bl
			jne		close_counter_false

			## if this is the ] bracket, check if it is the matching one
			decq	%r14 				# decrement counter, ] decreases by 1
			cmpq	$0, %r14 
			jnz		close_counter_false # if nested loop count is not zero, this is a nested bracket, skip since the counter isnt 0 yet
			popq	%r8					# we reached the end! it is the matching ] bracket
			xor		%r14, %r14			# clear counter
			incq	%r12				# next instruction
			jmp		interpret_start

			not_close_counter:
				incq	%r14			# increment nested loop counter
			close_counter_false:
				incq	%r12
				jmp		interpret_start

	interpret_end:

# release heap allocated memory
	movq	%r15, %rdi
	call 	free 	
	
	addq	$8, %rsp	
	pushq	%rbx
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15

	movq 	%rbp, %rsp
	popq 	%rbp
	ret

fast_print_char:
	movq 	$1, %rax # print to console
	movq	$1, %rdi # stdout
	movq	%r13, %rsi # %r13 is the cell pointer, it's already a reference to a char
	movq	$1,	%rdx # length = 1
	syscall
	ret
