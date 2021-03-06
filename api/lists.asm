; Night Kernel
; Copyright 2015 - 2020 by Mercury 0x0D
; lists.asm is a part of the Night Kernel

; The Night Kernel is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
; License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later
; version.

; The Night Kernel is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

; You should have received a copy of the GNU General Public License along with the Night Kernel. If not, see
; <http://www.gnu.org/licenses/>.

; See the included file <GPL License.txt> for the complete text of the GPL License by which this program is covered.





%include "include/listsDefines.inc"

%include "include/boolean.inc"
%include "include/CPU.inc"
%include "include/errors.inc"
%include "include/globals.inc"
%include "include/memory.inc"
%include "include/numbers.inc"
%include "include/screen.inc"





bits 32





section .text
LMBitfieldInit:
	; Creates a new bitfield from the parameters specified at the address specified
	;
	;  input:
	;	Address
	;	Number of bits
	;
	;  output:
	;	EAX - Total bytes occupied by this bitfield

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define bitCount							dword [ebp + 12]

	; allocate local variables
	sub esp, 4
	%define bitfieldSize						dword [ebp - 4]


	; calculate the total size of the memory this list will occupy
	; Rounding up needs done to keep things simple for the bitfield scanning routines, which process data by the DWord, not by the byte.
	; memory needed = (bits specified rounded up to the next highest multiple of 32, then divided by 8, plus 16 bytes for the header
	mov eax, bitCount
	and eax, 11111111111111111111111111100000b
	cmp eax, bitCount
	je .NoAdjust
		add eax, 32
	.NoAdjust:
	shr eax, 3
	add eax, 16
	mov bitfieldSize, eax

	; zero the space this list will occupy
	push 0
	push eax
	push address
	call MemFill


	; get the list ready for writing
	mov esi, address


	; write the data to the start of the list area, starting with the signature
	mov dword [esi + tBitfieldInfo.signature], 'bits'

	; initially all bits are clear, so we write setCount as zero
	mov dword [esi + tBitfieldInfo.setCount], 0

	; set elementCount to the number of bits in this bitfield
	mov eax, bitCount
	mov dword [esi + tBitfieldInfo.elementCount], eax

	; write total size of list
	mov eax, bitfieldSize
	mov dword [esi + tBitfieldInfo.listSize], eax


	.Exit:
	%undef address
	%undef bitCount
	%undef bitfieldSize
	mov esp, ebp
	pop ebp
ret 8





section .text
LMBitfieldScanClear:
	; Returns the number of the first clear bit in the bitfield
	;
	;  input:
	;	Bitfield address
	;	Sequence byte
	;
	;  output:
	;	EAX - Bit number
	;	EBX - Sequence byte
	;	EDX - Result code

	push ebp
	mov ebp, esp

	; define input parameters
	%define bitfieldAddress						dword [ebp + 8]
	%define sequenceByte						dword [ebp + 12]


	; round sequenceByte down to the lowest multiple of 4 since we process a DWord at a time
	and sequenceByte, 11111100b

	; validate sequenceByte
	mov esi, bitfieldAddress
	mov eax, sequenceByte
	add eax, 0x10
	cmp eax, dword [esi + tBitfieldInfo.listSize]
	jae .Fail

	; Now that we've validated the sequenceByte... what the fuzzy kitten nuts is it, anyway? Well, I'm glad you asked! ;)
	; In short, it's simply a time saving manoeuvre for cases where we will need to allocate a metric crapton of blocks in a row...
	; like filling a page table, for example. Instead of starting ALL THE WAY from the start of the table each time we search for
	; a block, we can simply feed the sequenceByte returned by the first call of this function back into the next call of it. Cool, huh? :D

	; adjust the address to allow for the bitfield header and load address into edi so we can SCASD the crap outta it!
	add bitfieldAddress, 0x10
	mov edi, bitfieldAddress

	; adjust starting address for the sequenceByte specified
	add edi, sequenceByte

	; use _THE MAGIC OF ASSEMBLY_ to find the first non-0xFFFFFFFF DWord in the bitfield
	; bytes to search = (bitfield length - header length - sequenceByte) / 4
	mov eax, 0xffffffff
	mov ecx, dword [esi + tBitfieldInfo.listSize]
	sub ecx, 0x10
	sub ecx, sequenceByte
	shr ecx, 2
	repz scasd 

	; adjust EDI back down to the thing we actually found
	sub edi, 4

	; Now that we found the first not-completely-filled DWord, we need to scan it to find the first clear bit with BSF.
	; I already hear you saying, "But wait! BSF only scans for SET bits, not CLEAR ones! And we need to look for clear bits here!"
	; and yes, you are correct. That just means we'll have to NOT the DWord first to make this work ;)
	mov eax, [edi]
	not eax
	mov ebx, 0
	bsf ebx, eax

	; now use EBX and ECX and the starting bit to calculate the position of this bit
	; position = (bytePosition - bitfieldAddress) * 8 + bitPosition
	mov eax, edi
	sub eax, bitfieldAddress
	shl eax, 3
	add eax, ebx

	; finally, adjust the sequenceByte to be returned
	mov ebx, edi
	sub ebx, bitfieldAddress


	; Baby get my order right, no err-ahs
	mov edx, kErrNone
	jmp .Exit

	; ooooooooooh, fail
	.Fail:
	mov edx, kErrInvalidParameter


	.Exit:
	%undef bitfieldAddress
	%undef sequenceByte
	mov esp, ebp
	pop ebp
ret 8





section .text
LMBitfieldScanSet:
	; Returns the number of the first set bit in the bitfield
	;
	;  input:
	;	Bitfield address
	;	Sequence byte
	;
	;  output:
	;	EAX - Bit number
	;	EBX - Sequence byte
	;	EDX - Result code

	push ebp
	mov ebp, esp

	; define input parameters
	%define bitfieldAddress						dword [ebp + 8]
	%define sequenceByte						dword [ebp + 12]


	; round sequenceByte down to the lowest multiple of 4 since we process a DWord at a time
	and sequenceByte, 11111100b

	; validate sequenceByte
	mov esi, bitfieldAddress
	mov eax, sequenceByte
	add eax, 0x10
	cmp eax, dword [esi + tBitfieldInfo.listSize]
	jae .Fail

	; adjust the address to allow for the bitfield header and load address into edi so we can SCASD the crap outta it!
	add bitfieldAddress, 0x10
	mov edi, bitfieldAddress

	; adjust starting address for the sequenceByte specified
	add edi, sequenceByte

	; use _THE MAGIC OF ASSEMBLY_ to find the first non-zero DWord in the bitfield
	; bytes to search = (bitfield length - header length - sequenceByte) / 4
	mov eax, 0
	mov ecx, dword [esi + tBitfieldInfo.listSize]
	sub ecx, 0x10
	sub ecx, sequenceByte
	shr ecx, 2
	repz scasd 

	; adjust EDI back down to the thing we actually found
	sub edi, 4

	; Now that we found the first not-completely-clear DWord, we need to scan it to find the first set bit with BSF.
	mov eax, [edi]
	mov ebx, 0
	bsf ebx, eax

	; now use EBX and ECX and the starting bit to calculate the position of this bit
	; position = (bytePosition - bitfieldAddress) * 8 + bitPosition
	mov eax, edi
	sub eax, bitfieldAddress
	shl eax, 3
	add eax, ebx

	; finally, adjust the sequenceByte to be returned
	mov ebx, edi
	sub ebx, bitfieldAddress


	; Havest we an error?
	mov edx, kErrNone
	jmp .Exit

	; strike three, kid
	.Fail:
	mov edx, kErrInvalidParameter


	.Exit:
	%undef bitfieldAddress
	%undef sequenceByte
	mov esp, ebp
	pop ebp
ret 8





section .text
LMBitfieldSpaceCalc:
	; Returns the amount of memory needed to hold a bitfield of the specified size
	;
	;  input:
	;	Number of bits
	;
	;  output:
	;	EAX - Total bytes which would be needed to hold the bitfield

	push ebp
	mov ebp, esp

	; define input parameters
	%define bitCount							dword [ebp + 8]


	; calculate the total size of the memory this bitfield will occupy
	mov eax, bitCount
	and eax, 11111111111111111111111111100000b
	cmp eax, bitCount
	je .NoAdjust
		add eax, 32
	.NoAdjust:
	shr eax, 3
	add eax, 16


	.Exit:
	%undef bitCount
	mov esp, ebp
	pop ebp
ret 4





section .text
LMBitfieldValidate:
	; Tests the bitfield specified for the 'bits' signature at the beginning
	;
	;  input:
	;	Bitfield address
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]


	; check list validity
	mov esi, address
	mov eax, dword [esi]
	mov edx, kErrBitfieldInvalid

	cmp eax, 'bits'
	jne .Exit

	mov edx, kErrNone


	.Exit:
	%undef address
	mov esp, ebp
	pop ebp
ret 4





section .text
LMBitfieldValidateElement:
	; Tests the element specified to be sure it not outside the bounds of the list
	;
	;  input:
	;	Bitfield address
	;	Element number
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]
	%define elementNum							dword [ebp + 12]


	; check element validity
	mov esi, listPtr
	mov eax, dword [esi + tBitfieldInfo.elementCount]

	cmp elementNum, eax
	mov edx, kErrValueTooHigh
	jae .Exit

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	%undef elementNum
	mov esp, ebp
	pop ebp
ret 8





section .text
LMBitClear:
	; Clears the bit specified within the bitfield at the address specified
	;
	;  input:
	;	Bitfield address
	;	Bit number
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define element								dword [ebp + 12]

	; allocate local variables
	sub esp, 12
	%define bitCountBefore						dword [ebp - 4]
	%define byteNumber							dword [ebp - 8]
	%define bitNumber							dword [ebp - 12]


	; see if the list is valid, exit if error
	push address
	call LMBitfieldValidate
	cmp edx, kErrNone
	jne .Exit

	; see if element is valid, exit if error
	push element
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit


	; get the byte and bit from the address and element
	push element
	push address
	call LM_Private_BitfieldMath
	mov byteNumber, ebx
	mov bitNumber, ecx

	; read the byte in
	mov eax, 0
	mov al, byte [ebx]

	; get the number of currently set bits in this byte
	push eax
	call PopulationCount
	mov bitCountBefore, edi

	; restore the important stuff
	mov ebx, byteNumber
	mov ecx, bitNumber
	mov eax, 0
	mov al, byte [ebx]

	; modify the bit
	btr eax, ecx

	; write the byte back to memory
	mov byte [ebx], al

	; get the number of currently set bits in this byte
	push eax
	call PopulationCount

	; update setCount
	mov esi, address
	mov eax, dword [esi + tBitfieldInfo.setCount]
	sub eax, bitCountBefore
	add eax, edi
	mov dword [esi + tBitfieldInfo.setCount], eax

	; all done!
	mov edx, kErrNone


	.Exit:
	%undef address
	%undef element
	%undef bitCountBefore
	%undef byteNumber
	%undef bitNumber
	mov esp, ebp
	pop ebp
ret 8





section .text
LMBitClearRange:
	; Clears the range of bits specified within the bitfield at the address specified
	;
	;  input:
	;	Bitfield address
	;	Bit range start
	;	Bit range end
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define rangeStart							dword [ebp + 12]
	%define rangeEnd							dword [ebp + 16]

	; allocate local variables
	sub esp, 20
	%define startByte							dword [ebp - 4]
	%define endByte								dword [ebp - 8]
	%define startBit							dword [ebp - 12]
	%define endBit								dword [ebp - 16]
	%define length								dword [ebp - 20]


	; see if the list is valid, exit if error
	push address
	call LMBitfieldValidate
	cmp edx, kErrNone
	jne .Exit

	; see if the parameters are valid, exit if error
	push rangeStart
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit

	push rangeEnd
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit


	; see which bytes will be at the start and end of this operation
	push rangeStart
	push address
	call LM_Private_BitfieldMath
	mov startByte, ebx
	mov startBit, ecx

	push rangeEnd
	push address
	call LM_Private_BitfieldMath
	mov endByte, ebx
	mov endBit, ecx


	; there's really no one-size-fits-all approach to bit range setting, so we implement three
	; (actually two and a half?) different scenarios here:
	; 1:	the range falls within a single byte
	; 2:	the range falls within two different bytes
	; 2.5:	the range already fell within two different bytes and they do not neighbor each other

	sub ebx, startByte
	cmp ebx, 0
	jne .NotASingleByte
		; if we get here, scenario 1 is true, so we can set up a simple loop to set all the bits needed in this byte
		push endBit
		push startBit
		push startByte
		push address
		call LM_Private_ByteClearRange
		jmp .Done
	.NotASingleByte:

	; if we get here, the range operation spans multiple bytes, so we process the first and last bytes... uh... first
	push 7
	push startBit
	push startByte
	push address
	call LM_Private_ByteClearRange

	push endBit
	push 0
	push endByte
	push address
	call LM_Private_ByteClearRange

	; Now we check to see if those bytes were neighbors (e.g. bytes 3 and 4, or 7 and 8). If so, there's no need to do anything further.
	mov ecx, endByte
	sub ecx, startByte
	cmp ecx, 2
	jl .Done


	; If we get here, the bytes were not neighbors, meaning there's space between them we can blanket with 0x00000000.
	; This is MUCH more efficient than setting each bit individually in sequence.

	; set up the number of bytes to process
	dec ecx
	mov length, ecx

	; adjust the startByte
	inc startByte

	; adjust setCount
	push length
	push startByte
	call PopulationCountRange

	; adjust setCount
	mov esi, address
	mov edx, [esi + tBitfieldInfo.setCount]
	sub edx, edi
	mov [esi + tBitfieldInfo.setCount], edx

	; set the starting addresses for the lodsd and stosd to come
	mov esi, startByte
	mov edi, esi

	; since we're processing DWords here first, ecx = length / 4
	mov eax, 0x00000000
	mov ecx, length
	shr ecx, 2
	cmp ecx, 0
	je .DWordLoopDone

	rep stosd
	.DWordLoopDone:


	; if the length was not evenly divisible by 4, we need to process the remaining bytes here
	mov ecx, length
	and ecx, 00000000000000000000000000000011b
	cmp ecx, 0
	je .ByteLoopDone

	rep stosb
	.ByteLoopDone:


	.Done:
	mov edx, kErrNone


	.Exit:
	%undef address
	%undef rangeStart
	%undef rangeEnd
	%undef startByte
	%undef endByte
	%undef startBit
	%undef endBit
	%undef length
	mov esp, ebp
	pop ebp
ret 12





section .text
LMBitFlip:
	; Flips (toggles) the bit specified within the bitfield at the address specified
	;
	;  input:
	;	Bitfield address
	;	Bit number
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define element								dword [ebp + 12]

	; allocate local variables
	sub esp, 12
	%define bitCountBefore						dword [ebp - 4]
	%define byteNumber							dword [ebp - 8]
	%define bitNumber							dword [ebp - 12]


	; see if the list is valid, exit if error
	push address
	call LMBitfieldValidate
	cmp edx, kErrNone
	jne .Exit

	; see if element is valid, exit if error
	push element
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit


	; get the byte and bit from the address and element
	push element
	push address
	call LM_Private_BitfieldMath
	mov byteNumber, ebx
	mov bitNumber, ecx

	; read the byte in
	mov eax, 0
	mov al, byte [ebx]

	; get the number of currently set bits in this byte
	push eax
	call PopulationCount
	mov bitCountBefore, edi

	; restore the important stuff
	mov ebx, byteNumber
	mov ecx, bitNumber
	mov eax, 0
	mov al, byte [ebx]

	; modify the bit
	btc eax, ecx

	; write the byte back to memory
	mov byte [ebx], al

	; get the number of currently set bits in this byte
	push eax
	call PopulationCount

	; update setCount
	mov esi, address
	mov eax, dword [esi + tBitfieldInfo.setCount]
	sub eax, bitCountBefore
	add eax, edi
	mov dword [esi + tBitfieldInfo.setCount], eax

	; all done!
	mov edx, kErrNone


	.Exit:
	%undef address
	%undef element
	%undef bitCountBefore
	%undef byteNumber
	%undef bitNumber
	mov esp, ebp
	pop ebp
ret 8





section .text
LMBitFlipRange:
	; Flips the range of bits specified within the bitfield at the address specified
	;
	;  input:
	;	Bitfield address
	;	Bit range start
	;	Bit range end
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define rangeStart							dword [ebp + 12]
	%define rangeEnd							dword [ebp + 16]

	; allocate local variables
	sub esp, 20
	%define startByte							dword [ebp - 4]
	%define endByte								dword [ebp - 8]
	%define startBit							dword [ebp - 12]
	%define endBit								dword [ebp - 16]
	%define length								dword [ebp - 20]


	; see if the list is valid, exit if error
	push address
	call LMBitfieldValidate
	cmp edx, kErrNone
	jne .Exit

	; see if the parameters are valid, exit if error
	push rangeStart
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit

	push rangeEnd
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit


	; see which bytes will be at the start and end of this operation
	push rangeStart
	push address
	call LM_Private_BitfieldMath
	mov startByte, ebx
	mov startBit, ecx

	push rangeEnd
	push address
	call LM_Private_BitfieldMath
	mov endByte, ebx
	mov endBit, ecx


	; there's really no one-size-fits-all approach to bit range setting, so we implement three
	; (actually two and a half?) different scenarios here:
	; 1:	the range falls within a single byte
	; 2:	the range falls within two different bytes
	; 2.5:	the range already fell within two different bytes and they do not neighbor each other

	sub ebx, startByte
	cmp ebx, 0
	jne .NotASingleByte
		; if we get here, scenario 1 is true, so we can set up a simple loop to set all the bits needed in this byte
		push endBit
		push startBit
		push startByte
		push address
		call LM_Private_ByteFlipRange
		jmp .Done
	.NotASingleByte:

	; if we get here, the range operation spans multiple bytes, so we process the first and last bytes... uh... first
	push 7
	push startBit
	push startByte
	push address
	call LM_Private_ByteFlipRange

	push endBit
	push 0
	push endByte
	push address
	call LM_Private_ByteFlipRange

	; Now we check to see if those bytes were neighbors (e.g. bytes 3 and 4, or 7 and 8). If so, there's no need to do anything further.
	mov ecx, endByte
	sub ecx, startByte
	cmp ecx, 2
	jl .Done


	; If we get here, the bytes were not neighbors, meaning there's space between them. We need to step through that space and apply a logical NOT

	; set up the number of bytes to process
	dec ecx
	mov length, ecx

	; adjust the startByte
	inc startByte

	; adjust setCount
	push length
	push startByte
	call PopulationCountRange
	mov esi, address
	mov edx, [esi + tBitfieldInfo.setCount]
	sub edx, edi
	mov [esi + tBitfieldInfo.setCount], edx

	; set the starting addresses for the lodsd and stosd to come
	mov esi, startByte
	mov edi, esi

	; since we're processing DWords here first, ecx = length / 4
	mov eax, 0xFFFFFFFF
	mov ecx, length
	shr ecx, 2
	cmp ecx, 0
	je .DWordLoopDone
		.DWordFlipLoop:
			lodsd
			not eax
			stosd
		loop .DWordFlipLoop
	.DWordLoopDone:


	; if the length was not evenly divisible by 4, we need to process the remaining bytes here
	mov ecx, length
	and ecx, 00000000000000000000000000000011b
	cmp ecx, 0
	je .ByteLoopDone
		.ByteFlipLoop:
			lodsb
			not al
			stosb
		loop .ByteFlipLoop
	.ByteLoopDone:


	.Done:
	; adjust setCount
	push length
	push startByte
	call PopulationCountRange
	mov esi, address
	mov edx, [esi + tBitfieldInfo.setCount]
	add edx, edi
	mov [esi + tBitfieldInfo.setCount], edx

	; no eee-rawrs
	mov edx, kErrNone


	.Exit:
	%undef address
	%undef rangeStart
	%undef rangeEnd
	%undef startByte
	%undef endByte
	%undef startBit
	%undef endBit
	%undef length
	mov esp, ebp
	pop ebp
ret 12





section .text
LMBitGet:
	; Returns the bit specified within the bitfield at the address specified
	;
	;  input:
	;	List address
	;	Bit number
	;
	;  output:
	;	EDX - Error code
	;	Carry Flag - Value of the bit specified

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define element								dword [ebp + 12]


	; see if the list is valid, exit if error
	push address
	call LMBitfieldValidate
	cmp edx, kErrNone
	jne .Exit

	; see if element is valid, exit if error
	push element
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit


	; get the byte and bit from the address and element
	push element
	push address
	call LM_Private_BitfieldMath

	; return the byte
	bt [ebx], ecx

	mov edx, kErrNone


	.Exit:
	%undef address
	%undef element
	mov esp, ebp
	pop ebp
ret 8





section .text
LMBitSet:
	; Sets the bit specified within the bitfield at the address specified
	;
	;  input:
	;	Bitfield address
	;	Bit number
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define element								dword [ebp + 12]

	; allocate local variables
	sub esp, 12
	%define bitCountBefore						dword [ebp - 4]
	%define byteNumber							dword [ebp - 8]
	%define bitNumber							dword [ebp - 12]


	; see if the list is valid, exit if error
	push address
	call LMBitfieldValidate
	cmp edx, kErrNone
	jne .Exit

	; see if element is valid, exit if error
	push element
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit


	; get the byte and bit from the address and element
	push element
	push address
	call LM_Private_BitfieldMath
	mov byteNumber, ebx
	mov bitNumber, ecx

	; read the byte in
	mov eax, 0
	mov al, byte [ebx]

	; get the number of currently set bits in this byte
	push eax
	call PopulationCount
	mov bitCountBefore, edi
	; restore the important stuff
	mov ebx, byteNumber
	mov ecx, bitNumber
	mov eax, 0
	mov al, byte [ebx]

	; modify the bit
	bts eax, ecx

	; write the byte back to memory
	mov byte [ebx], al

	; get the number of currently set bits in this byte
	push eax
	call PopulationCount

	; update setCount
	mov esi, address
	mov eax, dword [esi + tBitfieldInfo.setCount]
	sub eax, bitCountBefore
	add eax, edi
	mov dword [esi + tBitfieldInfo.setCount], eax

	; all done!
	mov edx, kErrNone


	.Exit:
	%undef address
	%undef element
	%undef bitCountBefore
	%undef byteNumber
	%undef bitNumber
	mov esp, ebp
	pop ebp
ret 8





section .text
LMBitSetRange:
	; Sets the range of bits specified within the bitfield at the address specified
	;
	;  input:
	;	Bitfield address
	;	Bit range start
	;	Bit range end
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define rangeStart							dword [ebp + 12]
	%define rangeEnd							dword [ebp + 16]

	; allocate local variables
	sub esp, 20
	%define startByte							dword [ebp - 4]
	%define endByte								dword [ebp - 8]
	%define startBit							dword [ebp - 12]
	%define endBit								dword [ebp - 16]
	%define length								dword [ebp - 20]


	; see if the list is valid, exit if error
	push address
	call LMBitfieldValidate
	cmp edx, kErrNone
	jne .Exit

	; see if the parameters are valid, exit if error
	push rangeStart
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit

	push rangeEnd
	push address
	call LMBitfieldValidateElement
	cmp edx, kErrNone
	jne .Exit


	; see which bytes will be at the start and end of this operation
	push rangeStart
	push address
	call LM_Private_BitfieldMath
	mov startByte, ebx
	mov startBit, ecx

	push rangeEnd
	push address
	call LM_Private_BitfieldMath
	mov endByte, ebx
	mov endBit, ecx


	; there's really no one-size-fits-all approach to bit range setting, so we implement three
	; (actually two and a half?) different scenarios here:
	; 1:	the range falls within a single byte
	; 2:	the range falls within two different bytes
	; 2.5:	the range already fell within two different bytes and they do not neighbor each other

	sub ebx, startByte
	cmp ebx, 0
	jne .NotASingleByte
		; if we get here, scenario 1 is true, so we can set up a simple loop to set all the bits needed in this byte
		push endBit
		push startBit
		push startByte
		push address
		call LM_Private_ByteSetRange
		jmp .Done
	.NotASingleByte:

	; if we get here, the range operation spans multiple bytes, so we process the first and last bytes... uh... first
	push 7
	push startBit
	push startByte
	push address
	call LM_Private_ByteSetRange

	push endBit
	push 0
	push endByte
	push address
	call LM_Private_ByteSetRange

	; Now we check to see if those bytes were neighbors (e.g. bytes 3 and 4, or 7 and 8). If so, there's no need to do anything further.
	mov ecx, endByte
	sub ecx, startByte
	cmp ecx, 2
	jl .Done


	; If we get here, the bytes were not neighbors, meaning there's space between them we can blanket with 0xFFFFFFFF.
	; This is MUCH more efficient than setting each bit individually in sequence. First, though, we need to account for the set bits already present.

	; set up the number of bytes to process
	dec ecx
	mov length, ecx

	; adjust the startByte
	inc startByte

	; adjust setCount
	push length
	push startByte
	call PopulationCountRange

	; adjust setCount
	mov esi, address
	mov edx, [esi + tBitfieldInfo.setCount]
	sub edx, edi
	mov ecx, length
	shl ecx, 3
	add edx, ecx
	mov [esi + tBitfieldInfo.setCount], edx

	; set the starting addresses for the lodsd and stosd to come
	mov esi, startByte
	mov edi, esi

	; since we're processing DWords here first, ecx = length / 4
	mov eax, 0xFFFFFFFF
	mov ecx, length
	shr ecx, 2
	cmp ecx, 0
	je .DWordLoopDone

	rep stosd
	.DWordLoopDone:


	; if the length was not evenly divisible by 4, we need to process the remaining bytes here
	mov ecx, length
	and ecx, 00000000000000000000000000000011b
	cmp ecx, 0
	je .ByteLoopDone

	rep stosb
	.ByteLoopDone:


	.Done:
	mov edx, kErrNone


	.Exit:
	%undef address
	%undef rangeStart
	%undef rangeEnd
	%undef startByte
	%undef endByte
	%undef startBit
	%undef endBit
	%undef length
	mov esp, ebp
	pop ebp
ret 12





section .text
LMCountBitsSet:
	; Returns the total number of set bits in the memory range specified
	;
	;  input:
	;	Start address
	;	Number of bytes to process
	;
	;  output:
	;	EDI - Result

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define length								dword [ebp + 12]


	mov esi, address
	mov edi, 0

	; since we're processing DWords here first, ecx = length / 4
	mov ecx, length
	shr ecx, 2
	cmp ecx, 0
	je .Exit

	.DWordCountLoop:
		lodsd
		popcnt ebx, eax
		add edi, ebx
	loop .DWordCountLoop


	; if the length was not evenly divisible by 4, we need to process the remaining bytes here
	mov ecx, length
	and ecx, 00000000000000000000000000000011b
	cmp ecx, 0
	je .Exit

	mov eax, 0
	.ByteCountLoop:
		lodsb
		popcnt ebx, eax
		add edi, ebx
	loop .ByteCountLoop


	.Exit:
	%undef address
	%undef length
	mov esp, ebp
	pop ebp
ret 8





section .text
LMElementAddressGet:
	; Returns the address of the specified element in the list specified
	;
	;  input:
	;	List address
	;	Element number
	;
	;  output:
	;	ESI - Element address
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]
	%define elementNum							dword [ebp + 12]


	; see if the list is valid
	push listPtr
	call LMListValidate

	; error check
	cmp edx, kErrNone
	jne .Exit

	; see if element is valid
	push elementNum
	push listPtr
	call LMElementValidate

	;error check
	cmp edx, kErrNone
	jne .Exit

	push elementNum
	push listPtr
	call LM_Private_ElementAddressGet

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	%undef elementNum
	mov esp, ebp
	pop ebp
ret 8





section .text
LMElementCountGet:
	; Returns the total number of elements in the list specified
	;
	;  input:
	;	List address
	;
	;  output:
	;	ECX - Number of total element slots in this list
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]


	push listPtr
	call LMListValidate

	; errror check
	cmp edx, kErrNone
	jne .Exit

	push listPtr
	call LM_Private_ElementCountGet

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	mov esp, ebp
	pop ebp
ret 4





section .text
LMElementCountSet:
	; Sets the total number of elements in the list specified
	;
	;  input:
	;	List address
	;	New number of total element slots in this list
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]
	%define newElementCount						dword [ebp + 12]


	push listPtr
	call LMListValidate

	; error check
	cmp edx, kErrNone
	jne .Exit

	push newElementCount
	push listPtr
	call LM_Private_ElementCountSet

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	%undef newElementCount
	mov esp, ebp
	pop ebp
ret 8





section .text
LMElementDelete:
	; Deletes the element specified from the list specified
	;
	;  input:
	;	List address
	;	Element number to be deleted
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]
	%define elementNum							dword [ebp + 12]


	push listPtr
	call LMListValidate

	; error check
	cmp edx, kErrNone
	jne .Exit

	push elementNum
	push listPtr
	call LMElementValidate

	;error check
	cmp edx, kErrNone
	jne .Exit

	push elementNum
	push listPtr
	call LM_Private_ElementDelete

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	%undef elementNum
	mov esp, ebp
	pop ebp
ret 8





section .text
LMElementDuplicate:
	; Duplicates the element specified in the list specified
	;
	;  input:
	;	List address
	;	Element number to be duplicated
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]
	%define elementNum							dword [ebp + 12]


	push listPtr
	call LMListValidate

	; error check
	cmp edx, kErrNone
	jne .Exit

	push elementNum
	push listPtr
	call LMElementValidate

	;error check
	cmp edx, kErrNone
	jne .Exit

	push elementNum
	push listPtr
	call LM_Private_ElementDuplicate

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	%undef elementNum
	mov esp, ebp
	pop ebp
ret 8





section .text
LMElementSizeGet:
	; Returns the elements size of the list specified
	;
	;  input:
	;	List address
	;
	;  output:
	;	EAX - List element size
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]


	push listPtr
	call LMListValidate

	; error check
	cmp edx, kErrNone
	jne .Exit

	push listPtr
	call LM_Private_ElementSizeGet
	mov eax, edx

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	mov esp, ebp
	pop ebp
ret 4





section .text
LMElementValidate:
	; Tests the element specified to be sure it not outside the bounds of the list
	;
	;  input:
	;	List address
	;	Element number
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]
	%define elementNum							dword [ebp + 12]


	; check element validity
	mov esi, listPtr
	mov eax, dword [esi + tListInfo.elementCount]

	cmp elementNum, eax
	mov edx, kErrValueTooHigh
	jae .Exit

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	%undef elementNum
	mov esp, ebp
	pop ebp
ret 8





section .text
LMItemAddAtSlot:
	; Adds an item to the list specified at the list slot specified
	;
	;  input:
	;	List address
	;	Slot at which to add element
	;	New item address
	;	New item size
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]
	%define slotNum								dword [ebp + 12]
	%define newItemPtr							dword [ebp + 16]
	%define newItemSize							dword [ebp + 20]


	push listPtr
	call LMListValidate

	; error check
	cmp edx, kErrNone
	jne .Exit

	push slotNum
	push listPtr
	call LMElementValidate

	;error check
	cmp edx, kErrNone
	jne .Exit

	push newItemSize
	push newItemPtr
	push slotNum
	push listPtr
	call LM_Private_ItemAddAtSlot

	mov edx, kErrNone


	.Exit:
	%undef listPtr
	%undef slotNum
	%undef newItemPtr
	%undef newItemSize
	mov esp, ebp
	pop ebp
ret 16





section .text
LMListCompact:
	; Compacts the list specified (eliminates empty slots to make list contiguous)
	;
	;  input:
	;	List address
	;
	;  output:
	;	n/a

	push ebp
	mov ebp, esp

	; define input parameters
	%define listPtr								dword [ebp + 8]


	push listPtr
	call LM_Private_ListCompact


	.Exit:
	%undef listPtr
	mov esp, ebp
	pop ebp
ret 4





section .text
LMListInit:
	; Creates a new list from the parameters specified at the address specified
	;
	;  input:
	;	Address
	;	Number of elements
	;	Size of each element
	;
	;  output:
	;	EAX - Total bytes occupied by this list

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define elementCount						dword [ebp + 12]
	%define elementSize							dword [ebp + 16]

	; allocate local variables
	sub esp, 4
	%define listSize							dword [ebp - 4]


	; calculate the total size of the memory this list will occupy
	mov eax, elementCount
	mov ebx, elementSize
	mov edx, 0x00000000
	mul ebx
	add eax, 16
	mov listSize, eax
	; might want to add code here later to check for edx being non-zero to indicate the list size is over 4 GB

	; zero the space this list will occupy
	push 0
	push eax
	push address
	call MemFill

	; get the list ready for writing
	mov esi, address


	; write the data to the start of the list area, starting with the signature
	mov dword [esi + tListInfo.signature], 'list'

	; write the size of each element next
	mov ebx, elementSize
	mov dword [esi + tListInfo.elementSize], ebx

	; write the total number of elements
	mov eax, elementCount
	mov dword [esi + tListInfo.elementCount], eax

	; write total size of list
	mov eax, listSize
	mov dword [esi + tListInfo.listSize], eax


	.Exit:
	%undef address
	%undef elementCount
	%undef elementSize
	%undef listSize
	mov esp, ebp
	pop ebp
ret 12





section .text
LMListSearch:
	; Searches all elements of the list specified for the data specified
	;
	;  input:
	;	List address
	;
	;  output:
	;	ESI - Memory address of element containing the matching data
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]


	push address
	call LM_Private_ListSearch


	.Exit:
	%undef address
	mov esp, ebp
	pop ebp
ret 4





section .text
LMListSpaceCalc:
	; Returns the amount of memory needed to hold a list of the specified size
	;
	;  input:
	;	Number of elements
	;	Size of each element
	;
	;  output:
	;	EAX - Total bytes which would be needed to hold the list

	push ebp
	mov ebp, esp

	; define input parameters
	%define elementCount						dword [ebp + 8]
	%define elementSize							dword [ebp + 12]


	; calculate the total size of the memory this list will occupy
	mov eax, elementCount
	mov ebx, elementSize
	mov edx, 0x00000000
	mul ebx
	add eax, 16


	.Exit:
	%undef elementCount
	%undef elementSize
	mov esp, ebp
	pop ebp
ret 8





section .text
LMListValidate:
	; Tests the list specified for the 'list' signature at the beginning
	;
	;  input:
	;	List address
	;
	;  output:
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]


	; check list validity
	mov esi, address
	mov eax, dword [esi]
	mov edx, kErrListInvalid

	cmp eax, 'list'
	jne .Exit

	mov edx, kErrNone


	.Exit:
	%undef address
	mov esp, ebp
	pop ebp
ret 4





section .text
LMSlotFindFirstFree:
	; Finds the first empty element in the list specified
	;
	;  input:
	;	List address
	;
	;  output:
	;	EAX - Element number of first free slot
	;	EDX - Error code

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]


	push address
	call LMListValidate

	; error check
	cmp edx, kErrNone
	jne .Exit

	push address
	call LM_Private_SlotFindFirstFree

	mov edx, kErrNone


	.Exit:
	%undef address
	mov esp, ebp
	pop ebp
ret 4





section .text
LMSlotFreeTest:
	; Tests the element specified in the list specified to see if it is free
	;
	;  input:
	;	List address
	;	Element number
	;
	;  output:
	;	EDX - Result
	;		true - Element empty
	;		false - Element not empty

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define elementNum							dword [ebp + 12]


	push address
	call LMListValidate

	; error check
	cmp edx, kErrNone
	jne .Exit

	push elementNum
	push address
	call LMElementValidate

	;error check
	cmp edx, kErrNone
	jne .Exit

	push elementNum
	push address
	call LM_Private_SlotFreeTest


	.Exit:
	%undef address
	%undef elementNum
	mov esp, ebp
	pop ebp
ret 8





section .text
LM_Private_BitfieldMath:
	; Returns the byte and bit based upon the address and element number specified
	;
	;  input:
	;	Address
	;	Element
	;
	;  output:
	;	EBX - byte address
	;	ECX - bit number

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define element								dword [ebp + 12]


	; calculate the offset from the address of the byte containing the specific bit needed
	; this can be done by shifting to divide by 8 (byteOffset = element / 8)
	mov eax, element
	shr eax, 3

	; calculate offset of bit needed inside the byte
	; (bitOffset = element − byteOffset × 8)
	mov ebx, eax
	shl ebx, 3
	mov ecx, element
	sub ecx, ebx

	; calculate actual byte address (address = 16 + address + byteOffset)
	mov ebx, address
	add ebx, eax
	add ebx, 16


	.Exit:
	%undef address
	%undef element
	mov esp, ebp
	pop ebp
ret 8





section .text
LM_Private_ByteClearRange:
	; Clears a range of bits in a single byte
	;
	;  input:
	;	Bitfield address
	;	Byte address
	;	Start of bit range
	;	End of bit range
	;
	;  output:
	;	n/a


	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define byteAddress							dword [ebp + 12]
	%define startBit							dword [ebp + 16]
	%define endBit								dword [ebp + 20]


	; load the byte on which we'll be working
	mov esi, byteAddress
	mov ebx, 0
	mov bl, [esi]

	; load and adjust setCount
	push ebx
	call PopulationCount
	mov esi, address
	sub dword [esi + tBitfieldInfo.setCount], edi

	; reload the byte on which we'll be working
	mov esi, byteAddress
	mov ebx, 0
	mov bl, [esi]

	; loop through and handle the bits
	mov edx, startBit
	mov ecx, endBit
	sub ecx, edx
	inc ecx
	.bitLoop:
		btr ebx, edx
		inc edx
	loop .bitLoop

	; write the finished byte back to memory
	mov [esi], bl

	; adjust and save setCount
	push ebx
	call PopulationCount
	mov esi, address
	add dword [esi + tBitfieldInfo.setCount], edi	


	.Exit:
	%undef address
	%undef byteAddress
	%undef startBit
	%undef endBit
	mov esp, ebp
	pop ebp
ret 16





section .text
LM_Private_ByteFlipRange:
	; Flips a range of bits in a single byte
	;
	;  input:
	;	Bitfield address
	;	Byte address
	;	Start of bit range
	;	End of bit range
	;
	;  output:
	;	n/a

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define byteAddress							dword [ebp + 12]
	%define startBit							dword [ebp + 16]
	%define endBit								dword [ebp + 20]


	; load the byte on which we'll be working
	mov esi, byteAddress
	mov ebx, 0
	mov bl, [esi]

	; load and adjust setCount
	push ebx
	call PopulationCount
	mov esi, address
	sub dword [esi + tBitfieldInfo.setCount], edi

	; reload the byte on which we'll be working
	mov esi, byteAddress
	mov ebx, 0
	mov bl, [esi]

	; loop through and handle the bits
	mov edx, startBit
	mov ecx, endBit
	sub ecx, edx
	inc ecx
	.bitLoop:
		btc ebx, edx
		inc edx
	loop .bitLoop

	; write the finished byte back to memory
	mov [esi], bl

	; adjust and save setCount
	push ebx
	call PopulationCount
	mov esi, address
	add dword [esi + tBitfieldInfo.setCount], edi	


	.Exit:
	%undef address
	%undef byteAddress
	%undef startBit
	%undef endBit
	mov esp, ebp
	pop ebp
ret 16





section .text
LM_Private_ByteSetRange:
	; Sets a range of bits in a single byte
	;
	;  input:
	;	Bitfield address
	;	Byte address
	;	Start of bit range
	;	End of bit range
	;
	;  output:
	;	n/a

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define byteAddress							dword [ebp + 12]
	%define startBit							dword [ebp + 16]
	%define endBit								dword [ebp + 20]


	; load the byte on which we'll be working
	mov esi, byteAddress
	mov ebx, 0
	mov bl, [esi]

	; load and adjust setCount
	push ebx
	call PopulationCount
	mov esi, address
	sub dword [esi + tBitfieldInfo.setCount], edi

	; reload the byte on which we'll be working
	mov esi, byteAddress
	mov ebx, 0
	mov bl, [esi]

	; loop through and handle the bits
	mov edx, startBit
	mov ecx, endBit
	sub ecx, edx
	inc ecx
	.bitLoop:
		bts ebx, edx
		inc edx
	loop .bitLoop

	; write the finished byte back to memory
	mov [esi], bl

	; adjust and save setCount
	push ebx
	call PopulationCount
	mov esi, address
	add dword [esi + tBitfieldInfo.setCount], edi	


	.Exit:
	%undef address
	%undef byteAddress
	%undef startBit
	%undef endBit
	mov esp, ebp
	pop ebp
ret 16





section .text
LM_Private_ElementAddressGet:
	; Returns the address of the specified element in the list specified
	;
	;  input:
	;	List address
	;	Element number
	;
	;  output:
	;	ESI - element address

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define elementNum							dword [ebp + 12]


	; get the size of each element in this list
	mov esi, address
	mov eax, [esi + tListInfo.elementSize]

	; calculate the new destination address
	mul elementNum
	lea esi, [eax + esi + 16]


	.Exit:
	%undef address
	%undef elementNum
	mov esp, ebp
	pop ebp
ret 8





section .text
LM_Private_ElementCountGet:
	; Returns the total number of elements in the list specified
	;
	;  input:
	;	List address
	;
	;  output:
	;	ECX - Number of total element slots in this list

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]


	; get the element size
	mov esi, address
	mov ecx, [esi + tListInfo.elementCount]


	.Exit:
	%undef address
	mov esp, ebp
	pop ebp
ret 4





section .text
LM_Private_ElementCountSet:
	; Sets the total number of elements in the list specified
	;
	;  input:
	;	List address
	;	New number of total element slots in this list
	;
	;  output:
	;	n/a

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define newSlotCount						dword [ebp + 12]


	; set the element size
	mov esi, address
	mov edx, newSlotCount
	mov [esi + tListInfo.elementCount], edx


	.Exit:
	%undef address
	%undef newSlotCount
	mov esp, ebp
	pop ebp
ret 8





section .text
LM_Private_ElementDelete:
	; Deletes the element specified from the list specified
	;
	;  input:
	;	List address
	;	Element number to be deleted
	;
	;  output:
	;	n/a

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define element								dword [ebp + 12]

	; allocate local variables
	sub esp, 12
	%define elementSize							dword [ebp - 4]
	%define elementCount						dword [ebp - 8]
	%define loopCounter							dword [ebp - 12]


	; get the element size of this list
	push address
	call LM_Private_ElementSizeGet
	mov elementSize, eax

	; get the number of elements in this list
	push dword 0
	push address
	call LM_Private_ElementCountGet

	; save the number of elements for later
	mov elementCount, ecx

	; set up a loop to copy down by one all elements from the one to be deleted to the end
	; Yes, we'll be modifying the contents of a passed parameter here, live and in-place. You got a problem with that? ;)
	dec ecx
	mov ebx, element
	sub ecx, ebx

	.ElementCopyLoop:
		
		; update the loop counter
		mov loopCounter, ecx

		; get the starting address of the destination element
		mov edx, element
		push edx
		mov eax, address
		push eax
		call LM_Private_ElementAddressGet

		; save the address we got
		push esi

		; get the starting address of the source element
		mov edx, element
		inc edx
		push edx
		push address
		call LM_Private_ElementAddressGet
		mov eax, esi

		; retrieve the previous address
		pop esi

		; copy the element data
		push elementSize
		push esi
		push eax
		call MemCopy

		; increment the index
		inc element

	mov ecx, loopCounter
	loop .ElementCopyLoop

	; update the number of elements in this list
	mov esi, address
	mov eax, dword [esi + tListInfo.elementCount]
	dec eax
	mov dword [esi + tListInfo.elementCount], eax

	; update the list's size field
	mov eax, dword [esi + tListInfo.listSize]
	sub eax, elementSize
	mov dword [esi + tListInfo.listSize], eax


	.Exit:
	%undef address
	%undef element
	%undef elementSize
	%undef elementCount
	%undef loopCounter
	mov esp, ebp
	pop ebp
ret 8





section .text
LM_Private_ElementDuplicate:
	; Duplicates the element specified in the list specified
	;
	;  input:
	;	List address
	;	Element number to be duplicated
	;
	;  output:
	;	n/a

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define element								dword [ebp + 12]

	; allocate local variables
	sub esp, 12
	%define elementSize							dword [ebp - 4]
	%define elementCount						dword [ebp - 8]
	%define loopCounter							dword [ebp - 12]


	; get the element size of this list
	push address
	call LM_Private_ElementSizeGet
	mov elementSize, eax

	; get the number of elements in this list
	push dword 0
	push address
	call LM_Private_ElementCountGet

	; increment the number of elements and save for later
	inc ecx
	mov elementCount, ecx

	; update the number of elements in this list
	push ecx
	push address
	call LM_Private_ElementCountSet

	; set up a loop to copy down by one all elements from the end to the one to be duplicated
	mov ecx, elementCount
	dec ecx
	mov ebx, element
	sub ecx, ebx

	.ElementCopyLoop:
		; update our loop counter
		mov loopCounter, ecx

		; get the starting address of the destination element
		dec elementCount
		mov edx, elementCount
		push edx
		push address
		call LM_Private_ElementAddressGet

		; save this address
		push esi

		; get the starting address of the source element
		mov edx, elementCount
		dec edx
		push edx
		push address
		call LM_Private_ElementAddressGet
		
		; retrieve the earlier saved address
		pop edi

		; copy the element data
		push elementSize
		push edi
		push esi
		call MemCopy

	mov ecx, loopCounter
	loop .ElementCopyLoop


	; update the list's size field
	mov esi, address
	mov eax, dword [esi + tListInfo.listSize]
	add eax, elementSize
	mov dword [esi + tListInfo.listSize], eax


	.Exit:
	%undef address
	%undef element
	%undef elementSize
	%undef elementCount
	%undef loopCounter
	mov esp, ebp
	pop ebp
ret 8





section .text
LM_Private_ElementSizeGet:
	; Returns the elements size of the list specified
	;
	;  input:
	;	List address
	;
	;  output:
	;	EAX - List element size

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]


	; get the element size
	mov esi, address
	mov eax, [esi + tListInfo.elementSize]


	.Exit:
	%undef address
	mov esp, ebp
	pop ebp
ret 4





section .text
LM_Private_ItemAddAtSlot:
	; Adds an item to the list specified at the list slot specified
	;
	;  input:
	;	List address
	;	Slot at which to add element
	;	New item address
	;	New item size
	;
	;  output:
	;	n/a

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define addSlot								dword [ebp + 12]
	%define newItemAddress						dword [ebp + 16]
	%define newItemSize							dword [ebp + 20]


	mov esi, address
	mov edx, addSlot


	; if we get here the list passed the data integrity check, so we proceed
	; get the size of each element in this list
	mov edi, address
	push edi
	call LM_Private_ElementSizeGet

	; now compare that to the given size of the new item
	cmp newItemSize, eax
	mov edx, kErrElementSizeInvalid

	; if we get here the size is ok, so we add it to the list!
	mov esi, newItemAddress
	mov ebx, newItemSize

	; calculate the new destination address
	mov edx, addSlot
	mul edx
	mov edi, address
	add eax, edi
	add eax, 16

	; prep the memory copy
	mov esi, newItemAddress
	mov ebx, newItemSize

	; copy the memory
	push ebx
	push eax
	push esi
	call MemCopy

	.Exit:
	%undef address
	%undef addSlot
	%undef newItemAddress
	%undef newItemSize
	mov esp, ebp
	pop ebp
ret 16





section .text
LM_Private_ListCompact:
	; Compacts the list specified (eliminates empty slots to make list contiguous)
	;
	;  input:
	;	List address
	;
	;  output:
	;	n/a

	push ebp
	mov ebp, esp


	
	mov esp, ebp
	pop ebp
ret 4





section .text
LM_Private_ListSearch:
	; Searches all elements of the list specified for the data specified
	;
	;  input:
	;	List address
	;
	;  output:
	;	ESI - Memory address of element containing the matching data

	push ebp
	mov ebp, esp



	mov esp, ebp
	pop ebp
ret 4





section .text
LM_Private_SlotFindFirstFree:
	; Finds the first empty element in the list specified
	;
	;  input:
	;	List address
	;
	;  output:
	;	EAX - Element number of first free slot

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]


	; load the list address
	mov esi, address

	; initialize our counter
	mov edx, 0x00000000

	; set up a loop to test all of the elements in this list
	.FindLoop:
		; save the counter
		push edx

		; test this element
		push edx
		push address
		call LM_Private_SlotFreeTest
		mov eax, edx

		; restore the counter
		pop edx

		; check the result
		cmp eax, true
		jne .ElementNotEmpty

		; if we get here, the element was empty
		jmp .Done

		.ElementNotEmpty:
		inc edx

	; see if we're done here
	mov ecx, [esi + tListInfo.elementCount]
	cmp edx, ecx
	jne .FindLoop

	.Done:
	mov eax, edx


	.Exit:
	%undef address
	mov esp, ebp
	pop ebp
ret 4





section .text
LM_Private_SlotFreeTest:
	; Tests the element specified in the list specified to see if it is free
	;
	;  input:
	;	List address
	;	Element number
	;
	;  output:
	;	EDX - Result
	;		true - element empty
	;		false - element not empty

	push ebp
	mov ebp, esp

	; define input parameters
	%define address								dword [ebp + 8]
	%define element								dword [ebp + 12]


	; calculate the element's address in RAM
	mov esi, address
	mov eax, [esi + tListInfo.elementSize]
	mul element
	add eax, esi
	add eax, 16

	; set up a loop to check each byte of this element
	mov ecx, [esi + tListInfo.elementSize]
	add eax, ecx
	mov edx, true
	.CheckElement:
		dec eax
		; load a byte from the element into bl
		mov bl, [eax]

		; test bl to see if it's empty
		cmp bl, 0x00

		; decide what to do
		je .ByteWasEmpty

		; if we get here, the byte wasn't empty, so we set a flag and exit this loop
		mov edx, false
		jmp .Exit

		.ByteWasEmpty:
	loop .CheckElement


	.Exit:
	%undef address
	%undef element
	mov esp, ebp
	pop ebp
ret 8
