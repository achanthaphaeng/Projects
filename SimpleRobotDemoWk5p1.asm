; This program includes...
; - Robot initialization (checking the battery, stopping motors, etc.).
; - The movement API.
; - Several useful subroutines (ATAN2, Neg, Abs, mult, div).
; - Some useful constants (masks, numbers, robot stuff, etc.)

; This code uses the timer interrupt for the movement control code.
; The ISR jump table is located in mem 0-4.  See manual for details.
ORG 0
	JUMP   Init        ; Reset vector
	RETI               ; Sonar interrupt (unused)
	JUMP   CTimer_ISR  ; Timer interrupt
	RETI               ; UART interrupt (unused)
	RETI               ; Motor stall interrupt (unused)

;***************************************************************
;* Initialization
;***************************************************************
Init:
	; Always a good idea to make sure the robot
	; stops in the event of a reset.
	LOAD   Zero
	OUT    LVELCMD     ; Stop motors
	OUT    RVELCMD
	STORE  DVel        ; Reset API variables
	STORE  DTheta
	OUT    SONAREN     ; Disable sonar (optional)
	OUT    BEEP        ; Stop any beeping (optional)
	
	CALL   SetupI2C    ; Configure the I2C to read the battery voltage
	CALL   BattCheck   ; Get battery voltage (and end if too low).
	OUT    LCD         ; Display battery voltage (hex, tenths of volts)
	
WaitForSafety:
	; This loop will wait for the user to toggle SW17.  Note that
	; SCOMP does not have direct access to SW17; it only has access
	; to the SAFETY signal contained in XIO.
	IN     XIO         ; XIO contains SAFETY signal
	AND    Mask4       ; SAFETY signal is bit 4
	JPOS   WaitForUser ; If ready, jump to wait for PB3
	IN     TIMER       ; We'll use the timer value to
	AND    Mask1       ;  blink LED17 as a reminder to toggle SW17
	SHIFT  8           ; Shift over to LED17
	OUT    XLEDS       ; LED17 blinks at 2.5Hz (10Hz/4)
	JUMP   WaitForSafety
	
WaitForUser:
	; This loop will wait for the user to press PB3, to ensure that
	; they have a chance to prepare for any movement in the main code.
	IN     TIMER       ; We'll blink the LEDs above PB3
	AND    Mask1
	SHIFT  5           ; Both LEDG6 and LEDG7
	STORE  Temp        ; (overkill, but looks nice)
	SHIFT  1
	OR     Temp
	OUT    XLEDS
	IN     XIO         ; XIO contains KEYs
	AND    Mask2       ; KEY3 mask (KEY0 is reset and can't be read)
	JPOS   WaitForUser ; not ready (KEYs are active-low, hence JPOS)
	LOAD   Zero
	OUT    XLEDS       ; clear LEDs once ready to continue

;***************************************************************
;* Main code
;***************************************************************
Main:
	OUT    RESETPOS    ; reset the odometry to 0,0,0
	; configure timer interrupt for the movement control code
	LOADI  10          ; period = (10 ms * 10) = 0.1s, or 10Hz.
	OUT    CTIMER      ; turn on timer peripheral
	SEI    &B0010      ; enable interrupts from source 2 (timer)
	; at this point, timer interrupts will be firing at 10Hz, and
	; code in that ISR will attempt to control the robot.
	; If you want to take manual control of the robot,
	; execute CLI &B0010 to disable the timer interrupt.
	
	;OUT    	RESETPOS
FirstRunInit:
	LOAD	StartXPOS
	OUT		XPOS
	LOAD	StartYPOS
	OUT		YPOS
	LOAD	Zero
	OUT		Theta
	;OUT		SSEG1
	IN		XPOS
	OUT		SSEG1
	CALL	Wait1
PhaseOne_Init:	
	;Set the wall distance values for Phase 1
	LOAD	PhaseOne_WallDistRight
	STORE	WallDistGood
;	OUT		SSEG2
	ADDI	100
	STORE	WallDistMax
	LOAD	WallDistGood
	ADDI	-100
	STORE	WallDistMin
	;Set Phase Transition Distances
	LOAD	PhaseOne_WallDistCutoff
	STORE	Cur_WallCutoff
	LOAD	PhaseOne_TurnDistShort
	STORE	Cur_MinTurnDist
	LOAD	PhaseOne_MaxDist
	STORE	Cur_MaxTurnDist
		
	LOAD	Zero
	STORE	NullValueCounter
	STORE	Can_Trans
	STORE	BotNotStraight
	
	IN		Theta
	STORE	OldDTheta
	STORE	DTheta
	
	LOAD   	FMid
	STORE  	DVel        ; use API to move forward
	
	;Start Phase 1
	LOAD	One
	STORE	PhaseNum
	OUT		LEDS
	LOAD	Zero
	STORE	NewPhase
	LOAD	Check1Hex
	OUT		LCD
	LOADI  	&B00100000		;Enable right-hand sonar only to maximize inputs to ensure proper wall distance
	OUT		SONAREN

	CALL	HSR_Body
	;Start Phase 2
	LOAD	OldDTheta
	STORE	DTheta
	ADDI	90
	STORE	OldDTheta
	CALL	Reset_Phase_Values_Zero
	LOADI  	&B00100000		;Enable right-hand sonar for wall distance checks
	OUT		SONAREN
	CALL	PhaseTwoThree_Init
	LOAD	Two
	STORE	PhaseNum
	OUT		XLEDS
	LOAD	Check2Hex
	OUT		LCD
	CALL	PhaseTwo
	
	;Start Phase 3, HSR 
		;No need to rest values after P2 as only TFAngle Changed and was reset already
	LOAD	Three
	STORE	PhaseNum
	OUT		LEDS
	LOAD	Check3Hex
	OUT		LCD
	LOAD   	FMid
	STORE  	DVel        ; use API to move forward

	CALL	HSR_Body
	;Start Phase 4-Resets
	CALL	Reset_Phase_Values_Zero
	LOADI  	&B00100000
	OUT		SONAREN
	CALL	PhaseFourFive_Init
	;Start Phase 4-RUN
	LOAD	Four
	STORE	PhaseNum
	OUT		LEDS
	LOAD	Check4Hex
	OUT		LCD
	
	CALL	PhaseFour
	;Start Phase 5
	LOAD	Zero
	STORE	OldDTheta
	LOAD	Five
	STORE	PhaseNum
	OUT		LEDS
	LOAD	Check5Hex
	OUT		LCD
	LOADI  	&B00000001		;Enable left-hand sonar
	OUT		SONAREN
	
	;TEMP die code for P1-4 checks
	LOAD   	FMid
	STORE  	DVel        ; use API to move forward
	
	CALL	HSR_Body
	;Start Phase 6-Resets
	LOAD	Zero
	STORE	DTheta
	ADDI	270
	STORE	OldDTheta		;Resets old dtheta for phase seven/eight
	CALL	Reset_Phase_Values_Zero
	LOADI  	&B00000001		;Enable left-hand sonar
	OUT		SONAREN
	CALL	PhaseSixSeven_Init
	;Start Phase 6-RUN
	LOAD	Six
	STORE	PhaseNum
	OUT		LEDS
	LOAD	Check6Hex
	OUT		LCD
	LOAD	DTheta
	OUT		SSEG1
	LOAD	Check6Hex
	OUT		SSEG2
	CALL	WAIT1
	
	CALL	PhaseSix
	;Start Phase 7
	LOAD	Zero
	STORE	OldDTheta
	LOAD	Seven
	STORE	PhaseNum
	OUT		LEDS
	LOAD	Check7Hex
	OUT		LCD
	LOAD   	FMid
	STORE  	DVel        ; use API to move forward
	
	CALL	HSR_Body
;	JUMP	Die
	;Start Phase 8
	CALL	PhaseEight
	JUMP	PhaseOne_Init

HSR_Body:
	;Basic High Speed Run code
	IN		XPOS
	OUT		SSEG1
	CALL	InWallDist_Base		;Check the distance to the right
	LOAD	CurWallDist				
	SUB		NULLDistanceValue		;Check the wall distance to see if this is a null value, &H7FFF
	JNEG	HSR_CheckDist			;If Not null, go to the next check
	CALL	NullValueCounter
	JUMP	HSR_Body				;Start over
HSR_CheckDist:
	;Reset Null as we know it's good
	LOAD	Zero
	STORE	NumNullVals
	;AVG Wall Distance (currently 4 pt)
	CALL	AVGWallDistCalc
	;Check to see if we have gone far enough to transition to p2
	LOAD	Can_Trans
	JPOS	HSR_TransCall
	CALL	Can_Transition_Phase
	LOAD	Can_Trans
	JZERO	HSR_GoStraight
HSR_TransCall:
	LOAD   	FSlow
	STORE  	DVel        ;Slow down for data acquisition
	CALL	VariousPhase_TransCall
	CALL	TransitionCheck_Body
	LOAD	NewPhase
	JZERO	HSR_GoStraight
	LOAD	Zero
	STORE	DVel
	LOAD	CurPOS_WallDist
	OUT		SSEG2
	IN		YPOS
	OUT		SSEG1
	CALL	WAIT1
	RETURN
HSR_GoStraight:
	LOAD	AVGWallDist
	SUB		WallDistMin
	JPOS	HSR_CheckFar
	LOAD	BotNotStraight
	JNEG	HSR_Body				;If BNS=-1, Bot has already made the first correction turn
	CALL	TooCloseToWall
	JUMP	HSR_Body
HSR_CheckFar:
	LOAD	AVGWallDist
	SUB		WallDistMax
	JNEG	HSR_NowGood
	LOAD	BotNotStraight
	JPOS	HSR_Body				;If BNS=1, Bot has already made the first correction turn
	CALL	TooFarFromWall
	STORE	BotNotStraight
HSR_NowGood:
	LOAD	BotNotStraight
	JZERO	HSR_Body		;If already zero, no need to correct
	CALL	NowGoodDistFromWall
	JUMP 	HSR_Body
HSR_TurnLeft:	
	CALL	TurnLeft_Ten
	LOAD	Zero
	STORE	BotNotStraight
	JUMP 	HSR_Body

PhaseTwo:		;This is a suitable template for P4 and P6 as well with no issues in implementation
					;It can also be used as a basis for Phase 8, which has two such turns
					;The position checks during the turn must be added
	;This is simply a 90 degree turn to the left
	CALL	Wait1
	CALL	Turn
	;Reset TFAngle for nest run, only variable to change in P2
	LOAD	Zero
	STORE	TFAngle
	LOAD   	FMid
	STORE  	DVel        ; send robot forward
	RETURN
PhaseFour:
	;This is a 180 degree turn, in two 90 degreee segments that check the wall distance
	IN		Theta
	STORE	OldDTheta
	CALL	InWallDist_Right
	LOAD	CurWallDist
	STORE	YPOS_Check
	OUT		SSEG1
	CALL	Wait1				;Error check
	LOAD	ZERO
	ADDI	90
	STORE	TFAngle
	CALL	Turn
	CALL	InWallDist_Right
	LOAD	CurWallDist
	STORE	XPOS_Check
	OUT		SSEG2
	CALL	Wait1				;Error check
	LOAD	ZERO
	ADDI	90
	STORE	TFAngle
	CALL	Turn
	;Reset TFAngle and CurWallDist for nest run, only variables to change in P4
	LOAD	Zero
	STORE	TFAngle
	STORE	CurWallDist
	STORE	DTheta
	; reset the odometry to 0,0,0, then reset X/Y based on the reference corner
	OUT    	RESETPOS    
	LOAD	XPOS_Check
	OUT		XPOS
	OUT		SSEG1
	LOAD	YPOS_Check
	OUT		YPOS
	OUT		SSEG2
	LOAD	Check1Hex
	OUT		LCD
	CALL	WAIT1
	CALL	LastChanceGoodRunCheck
;	LOAD   	FMid
;	STORE  	DVel        ; send robot forward
	RETURN
PhaseSix:		
	;This is simply a 90 degree turn to the right
	CALL	Wait1
	LOAD	ZERO
	ADDI	-90
	STORE	TFAngle
	CALL	Turn
	;DONT Reset TFAngle for nest run as P* needs it twice
;	LOAD	Zero
;	STORE	TFAngle
;	LOAD   	FMid
;	STORE  	DVel        ; send robot forward
	RETURN
PhaseEight:
	;This is a 180 degree turn, in two 90 degreee segments that check the wall distance
	IN		Theta
	STORE	OldDTheta
	CALL	InWallDist_Left
	LOAD	CurWallDist
	STORE	YPOS_Check
	OUT		SSEG1
	CALL	Wait1				;Error check
	LOAD	ZERO
	ADDI	270
	STORE	TFAngle
	CALL	Turn
	CALL	InWallDist_Left
	LOAD	CurWallDist
	STORE	XPOS_Check
	OUT		SSEG2
	CALL	Wait1				;Error check
	LOAD	ZERO
	ADDI	270
	STORE	TFAngle
	CALL	Turn
	;Reset TFAngle and CurWallDist for nest run, only variables to change in P4
	LOAD	Zero
	STORE	TFAngle
	STORE	CurWallDist
	STORE	DTheta
	; reset the odometry to 0,0,0, then reset X/Y based on the reference corner
	OUT    	RESETPOS    
	LOAD	XPOS_Check
	OUT		XPOS
	LOAD	YPOS_Check
	OUT		YPOS
	CALL	LastChanceGoodRunCheck
;	LOAD   	FMid
;	STORE  	DVel        ; send robot forward
	RETURN
	
LastChanceGoodRunCheck:
	;This block looks at the value from the right (P4) or left (P8) sonar after the first 90 degree turn and checks to make sure we are in the goal area
		;If below the cutoff for that phase, continue as normal
		;If above that value, turn back, go straight again, and repeat the process from the check distance value
	LOAD	XPOS_Check						;In both cases, the distacne to the wall/podium is the XPOS check value
	OUT		SSEG2
	SUB		Current_LastChanceCutoff
	STORE	Temp
	OUT		SSEG1
	LOAD	Check2Hex
	OUT		LCD
	CALL	Wait1
	JPOS	GoFurther
	RETURN
GoFurther:
	;We are only partially in the good area, and must go forward more
	;However, we are facing the right direction and just need to back up in the XPOS direction
	IN		XPOS
	SUB		Temp	;This gives us the XPOS value that we must reach to be in the good area entirely
	STORE	XPOS_Check		;We have already used this to reset our XPOS by now
	LOAD	RSlow
	STORE	DVel
	;Now check for distance in reverese (loop)
ReverseLoop:
	IN		XPOS
	SUB		XPOS_Check
	JPOS	ReverseLoop
	LOAD	Zero
	STORE	DVel
	RETURN
	
WallDistTrend:
	;This checks the wall distance half a second before and compared it to the current value. 
		;If distance increasing, turn back towards wall
		;If decreasing, turn away
		RETURN

VariousPhase_TransCall:
	;Check the phase number to ensure the calls are correct
		;P1		XPOS		AVGWallDist
		;P3		YPOS		WallAhead
		;P5		XPOS		WallAhead
		;P7		-?YPOS		WallAhead
	LOAD	PhaseNum
	ADDI	-3				;1 -> -2	3 -> 0	5 -> 2	7 -> 4
	JNEG	P1_TransCall
	JZERO	P3_TransCall
	ADDI	-4				;					5 -> -2	7 -> 0
	JNEG	P5_TransCall
	JZERO	P7_TransCall
P1_TransCall:
	IN		XPOS
	STORE	CurPOS_TurnCheck
	LOAD	AVGWallDist
	STORE	CurPOS_WallDist
	RETURN
P3_TransCall:
	IN		YPOS
	STORE	CurPOS_TurnCheck
	CALL	InWallDist_3Only
	LOAD	CurWallDistAhead
	STORE	CurPOS_WallDist
	RETURN
P5_TransCall:
	IN		XPOS
	STORE	CurPOS_TurnCheck
;	CALL	InWallDist_3Only
	CALL	InWallDist_2Only
	LOAD	CurWallDistAhead
	STORE	CurPOS_WallDist
	RETURN
P7_TransCall:
	IN		YPOS
	STORE	CurPOS_TurnCheck
;	CALL	InWallDist_3Only
	CALL	InWallDist_2Only
	LOAD	CurWallDistAhead
	STORE	CurPOS_WallDist
	RETURN

	
TooCloseToWall:
	;Check the phase number to see which direction to turn
	LOAD	PhaseNum
	ADDI	-4					;1 -> -3	3 -> -1		5 -> 1		7 -> 3
	JNEG	Close_TurnLeftCall	;If too close in P1 or P3, the bot corrects by turning left, so as in P1 or P3 jump to turn left
	CALL	TurnRight_Ten
	LOAD	NegOne
	STORE	BotNotStraight
	RETURN	
Close_TurnLeftCall:
	CALL	TurnLeft_Ten
	LOAD	NegOne
	STORE	BotNotStraight
	RETURN
	
TooFarFromWall:
	;Check the phase number to see which direction to turn
	LOAD	PhaseNum
	ADDI	-4
	JNEG	Far_TurnRightCall	;If too far in P1 or P3, the bot corrects by turning right, so as in P1 or P3 jump to turn right
	CALL	TurnLeft_Ten
	LOAD	One
	STORE	BotNotStraight
	RETURN	
Far_TurnRightCall:
	CALL	TurnRight_Ten
	LOAD	One
	STORE	BotNotStraight
	RETURN
	
	JNEG	HSR_TurnLeft	;If -1, the robot was too close but is now back in the goldilocks zone
	CALL	TurnRight_Ten	;Else, the value is 1 and the bot was too far but is now back in the goldilocks zone

NowGoodDistFromWall:
	;Check the phase number to see which direction to turn
	LOAD	BotNotStraight
	JNEG	WasTooClose
WasTooFar:
	LOAD	PhaseNum
	ADDI	-4
	JNEG	Good_TurnLeft		;If too far in P1 or P3, the bot corrects by turning right, so now must turn back to the left
	JUMP	Good_TurnRight		;If too far in P5 or P7, the bot corrects by turning left, so now must turn back to the right
WasTooClose:
	LOAD	PhaseNum
	ADDI	-4
	JNEG	Good_TurnRight		;If too close in P1 or P3, the bot corrects by turning left, so now must turn back to the right
	JUMP	Good_TurnLeft		;If too close in P5 or P7, the bot corrects by turning right, so now must turn back to the left
Good_TurnLeft:
	CALL	TurnLeft_Ten
	LOAD	Zero
	STORE	BotNotStraight
	RETURN
Good_TurnRight:
	CALL	TurnRight_Ten
	LOAD	Zero
	STORE	BotNotStraight
	RETURN

TurnRight_Ten:
	LOAD	DTheta
	ADDI	-10
	CALL	Mod360
	STORE	DTheta
	RETURN
TurnLeft_Ten:
	LOAD	DTheta
	ADDI	10
	CALL	Mod360
	STORE	DTheta
	RETURN


InWallDist_Base:
	LOAD	PhaseNum
	ADDI	-4
	JPOS	InWallDist_Left		;P1-3 look right, P5-7 look left
InWallDist_Right:		;Read the wall distance to the right (P1,3) and store as Current Wall Distance
	IN		DIST5
	STORE	CurWallDist
;	OUT		SSEG1
	RETURN
InWallDist_Left:
	IN		DIST0
	STORE	CurWallDist
;	OUT		SSEG1
	RETURN
	
InWallDist_3Only:
	IN		DIST3
;	STORE	Temp
;	ADDI	-1200
;	JNEG	Dist3OK
	;If this reads positive, then the value is much too huigh and the bot is either:
		;Not close enough		Unlikely given the tested odometry puts us close enough
		;Looking at the desk	Should turn to the right, but unlikely for DIST 3
		;NULL					Too far right or left, so correct in both directions
;	LOAD	TEMP
;	SUB		NULLDistanceValue
;	JZERO	DIST3IN_NULL
	;Assuming not null, must be looking at the desk, turn 10 degrees to the right (-10)
;	CALL	TurnRight_Ten
;	CALL	WAIT1
;	JUMP	InWallDist_3Only
;DIST3IN_NULL:
;	CALL	TurnLeft_Ten
;	CALL	WAIT1
;	JUMP	InWallDist_3Only	
;Dist3OK:
;	LOAD	TEMP
;	SHIFT	1
	STORE	CurWallDistAhead
	RETURN
	
InWallDist_2Only:
	IN		DIST2
;	STORE	Temp
;	ADDI	-1200
;	JNEG	Dist2OK
	;If this reads positive, then the value is much too huigh and the bot is either:
		;Not close enough		Unlikely given the tested odometry puts us close enough
		;Not Looking at podium	Should turn to the left, but unlikely for DIST 2
		;NULL					Too far right or left, so correct in both directions, but really away
;	LOAD	TEMP
;	SUB		NULLDistanceValue
;	JZERO	DIST2IN_NULL
	;Assuming not null, must be looking at the desk, turn 10 degrees to the right (-10)
;	CALL	TurnLeft_Ten
;	CALL	WAIT1
;	JUMP	InWallDist_2Only
;D;IST2IN_NULL:
;	CALL	TurnRight_Ten
;	CALL	WAIT1
;	JUMP	InWallDist_2Only	
;Dist2OK:
;	LOAD	TEMP
;	SHIFT	1
	STORE	CurWallDistAhead
	RETURN
		
Can_Transition_Phase:
	;This current section will need to be modified as new phase checks are added
		;Currently only for Phase 1 to 2 Transition
	LOAD	PhaseNum
	ADDI	-1
	JPOS	PhaseThree_CheckEnable	;Check next phase
	;Are we even in the ballpark for the checks?
	IN		XPOS
	SUB		PhaseOne_EnableChecksDist
	JNEG	GOBACK
	LOAD	One
	STORE	Can_Trans
	LOADI  	&B00101100		;Enable ahead sonars, as since bot slowing down can use these w/o impacting left/right wall distance
	OUT		SONAREN
	RETURN
PhaseThree_CheckEnable:
	LOAD	PhaseNum
	OUT		SSEG1
	ADDI	-3
	JPOS	PhaseFive_CheckEnable	;Check next phase
	;Are we even in the ballpark for the checks?
	IN		YPOS
	SUB		PhaseThree_EnableChecksDist
	JNEG	GOBACK
	LOAD	One
	STORE	Can_Trans
	LOADI  	&B00101100
	OUT		SONAREN
	RETURN
PhaseFive_CheckEnable:
	LOAD	PhaseNum
	OUT		SSEG1
	ADDI	-5
	JPOS	PhaseSeven_CheckEnable	;Check next phase
	;Are we even in the ballpark for the checks?
	IN		XPOS
	SUB		PhaseFive_EnableChecksDist
	JNEG	GOBACK
	LOAD	One
	STORE	Can_Trans
	LOADI  	&B00001101		;Enable ahead sonars
	OUT		SONAREN
PhaseSeven_CheckEnable:
	IN		YPOS
	ADD		PhaseSeven_EnableChecksDist
	JPOS	GOBACK
	LOAD	One
	STORE	Can_Trans
	LOADI  	&B00001101		;Enable ahead sonars
	OUT		SONAREN
	RETURN

GOBACK:	
	RETURN

PhaseTwoThree_Init:
	;Set Wall Distance variables for the next run (Phase 3)
	LOAD	PhaseThree_WallDistRight
	STORE	WallDistGood
;	OUT		SSEG2
	ADDI	50
	STORE	WallDistMax
	LOAD	WallDistGood
	ADDI	-50
	STORE	WallDistMin
	;Set cutoff distance for Phase 3
	LOAD	PhaseThree_WallDistCutoff
	STORE	Cur_WallCutoff
	LOAD	PhaseThree_TurnDistShort
	STORE	Cur_MinTurnDist
	LOAD	PhaseThree_MaxDist
	STORE	Cur_MaxTurnDist
	
;	LOAD	Zero
;	OUT		SSEG2
	LOAD	ZERO
	ADDI	90
	STORE	TFAngle
	;Set the PhaseNo. to 2
	;Make the return to start the turn
	RETURN
PhaseFourFive_Init:
	LOAD	PhaseFive_WallDistLeft
	STORE	WallDistGood
;	OUT		SSEG2
	ADDI	100
	STORE	WallDistMax
	LOAD	WallDistGood
	ADDI	-100
	STORE	WallDistMin
	;Set cutoff distance for Phase 5
	LOAD	PhaseFive_WallDistCutoff
	STORE	Cur_WallCutoff
	LOAD	PhaseFive_TurnDistShort
	STORE	Cur_MinTurnDist
	LOAD	PhaseFive_MaxDist
	STORE	Cur_MaxTurnDist
	LOAD	PhaseFour_LastChanceCutoff
	STORE	Current_LastChanceCutoff
	OUT		SSEG1
	CALL	Wait1
PhaseSixSeven_Init:
	LOAD	PhaseSeven_WallDistLeft
	STORE	WallDistGood
;	OUT		SSEG2
	ADDI	100
	STORE	WallDistMax
	LOAD	WallDistGood
	ADDI	-100
	STORE	WallDistMin
	;Set cutoff distance for Phase 7
	LOAD	PhaseSeven_WallDistCutoff
	STORE	Cur_WallCutoff
	LOAD	PhaseSeven_TurnDistShort
	STORE	Cur_MinTurnDist
	LOAD	PhaseSeven_MaxDist
	STORE	Cur_MaxTurnDist
	LOAD	Zero
	ADDI	-90
	STORE	TFAngle
	LOAD	PhaseEight_LastChanceCutoff
	STORE	Current_LastChanceCutoff

Reset_Phase_Values_Zero:
	LOAD	Zero
	STORE	NullValueCounter
	STORE	NumNullVals
	STORE	Temp
	STORE	Temp2
	
	STORE	Can_Trans
	STORE	NewPhase
	STORE  	TFAngle
	STORE	BotNotStraight
	STORE	CurPOS_TurnCheck
	STORE	CurPOS_WallDist
	STORE	Current_LastChanceCutoff
	
	STORE	CurWallDist
	STORE	WallDist1
	STORE	WallDist2
	STORE	WallDist3
	STORE	WallDist4
	STORE	Quad_AVGWallDist
	STORE	AVGWallDist
	STORE	CurWallDistAhead
	
	OUT		SSEG1
	OUT		SSEG2
	RETURN	
	
Turn:                  ; turns robot relative to current angle
	LOAD   	DVel
	OUT 	SSEG2
	STORE  	TFDVel      ; store current velocity
	LOAD  	Zero
	STORE  	DVel        ; stop robot
	LOAD   	DTheta
	ADD    	TFAngle     ; calculate absolute angle
	CALL	Mod360
	STORE  	DTheta      ; use API to get robot to face new angle
	Call	Wait1
	OUT		SSEG1
	CALL	Wait1
	STORE  	NewTFAngle     ; store abosulate angle for future use
	RETURN
;TurnLoop:
;	OUT 	SSEG2
;	IN     Theta
;	SUB    TFAngle
;	CALL   Abs         ; get abs(currentAngle - targetAngle)
;	ADDI   -3
;	JPOS   TurnLoop    ; if angle error > 3, keep checking
	; at this point, robot should be within 3 degrees of target angle

NullValueCounter:
	LOAD	NumNullVals
	ADDI	1
	STORE	NullValueCounter
	ADDI	-4
	JPOS	TooManyNulls
	RETURN
TooManyNulls:
	;This is set after recieving too many null values in a row
	LOAD	Zero
	STORE	NullValueCounter
	LOAD 	OldDTheta
	STORE	DTheta
	RETURN

AVGWallDistCalc:
	LOAD	AVGWallDist
	JZERO	FirstAVG
	
	LOAD	WallDist2
	STORE	WallDist1
	
	LOAD	WallDist3
	STORE	WallDist2
	
	LOAD	WallDist4
	STORE	WallDist3
	
	LOAD	CurWallDist
	STORE	WallDist4
	
	LOAD	Zero
	ADD		WallDist1
	ADD		WallDist2
	ADD		WallDist3
	ADD		WallDist4
	STORE	Quad_AVGWallDist
	SHIFT	-2
	STORE	AVGWallDist
	OUT		SSEG2
	
	LOAD	LastWallDistCount
	ADDI	1
	STORE	LastWallDistCount
	SUB		Four
	JNEG	GOBACK
	CALL	WallDistTrend
	
	RETURN
FirstAVG:
	LOAD	CurWallDist
	STORE	AVGWallDist
	STORE	WallDist1
	STORE	WallDist2
	STORE	WallDist3
	STORE	WallDist4
	OUT		SSEG2
	LOAD	CurWallDist
	STORE	LastWallDistAVG
	SHIFT	2
	STORE	Quad_AVGWallDist
	LOAD	Zero
	STORE	LastWallDistCount
	RETURN
		
Die:
; Sometimes it's useful to permanently stop execution.
; This will also catch the execution if it accidentally
; falls through from above.
	CLI    &B1111      ; disable all interrupts
	LOAD   Zero        ; Stop everything.
	OUT    LVELCMD
	OUT    RVELCMD
	OUT    SONAREN
	LOAD   DEAD        ; An indication that we are dead
	OUT    SSEG2       ; "dEAd" on the sseg
Forever:
	JUMP   Forever     ; Do this forever.
	DEAD:  DW &HDEAD   ; Example of a "local" variable


; Timer ISR.  Currently just calls the movement control code.
; You could, however, do additional tasks here if desired.
CTimer_ISR:
	CALL   ControlMovement
	RETI   ; return from ISR
	
	
TransitionCheck_Body:
	;First check to see if over the minimum turn distance
	LOAD	CurPOS_TurnCheck		
	SUB		Cur_MinTurnDist
	JPOS	TC_OverMin
	LOAD	PhaseNum
	ADDI	-7
	JZERO	TransCheck_Phase7Unique
	RETURN				;Not far enough
TC_OverMin:
	;Now check if the sonar cutoff has been met, if read in distance is too low then turn, else, check if too far
	LOAD	CurPOS_WallDist
	SUB		Cur_WallCutoff
	JNEG	TC_Transition
	;Now Check if over the maximum distance
	LOAD	CurPOS_TurnCheck		
	SUB		Cur_MaxTurnDist
	JPOS	TC_Transition
	RETURN
TC_Transition:
	LOAD	CurPOS_WallDist
	OUT		SSEG2
	IN		YPOS
	OUT		SSEG1
	CALL	WaitP1
	LOAD	One
	STORE	NewPhase
	RETURN
TransCheck_Phase7Unique:		;The phase seven checks all assume the odometry check distances are still positive, as this make the easiest comparison for the negative YPOS values
	LOAD	CurPOS_TurnCheck		
	ADD		Cur_MinTurnDist
	JNEG	TC_OverMin_P7
	RETURN				;Not far enough
TC_OverMin_P7:
	LOAD	CurPOS_WallDist
	SUB		Cur_WallCutoff
	JNEG	TC_Transition
	;Now Check if over the maximum distance
	LOAD	CurPOS_TurnCheck		
	ADD		Cur_MaxTurnDist
	JNEG	TC_Transition
	RETURN

	
	
;Odometry values, all adjusted
StartXPOS:					DW	43		;45cm/1.05mm=42.86, call it 43
StartYPOS:					DW	86		;90cm/1.05mm=85.71, call it 86

;PhaseOne_EnableChecksDist:		DW	2850	;3.5m/1.05mm=3333, call it 3350				-50cm
PhaseOne_TurnDistShort:			DW	3310	;4.0m/1.05mm=3809.5							-50cm
PhaseOne_MaxDist:				DW	3500	;4.2m/1.05mm=4000							-50cm
PhaseOne_EnableChecksDist:		DW	3350	;3.5m/1.05mm=3333, call it 3350
;PhaseOne_TurnDistShort:			DW	3810	;4.0m/1.05mm=3809.5
;PhaseOne_MaxDist:				DW	4000	;4.2m/1.05mm=4000

;PhaseThree_TurnDistShort:		DW	4321	;4.8m/1.05mm=4571.43, call 4571				-25cm
;PhaseThree_MaxDist:				DW	4512	;5.0m/1.05mm=4761.90, call 4762				-25cm
PhaseThree_TurnDistShort:		DW	4171	;4.8m/1.05mm=4571.43, call 4571				-40cm
PhaseThree_MaxDist:				DW	4362	;5.0m/1.05mm=4761.90, call 4762				-40cm
;PhaseThree_EnableChecksDist:	DW	3310	;4.0m/1.05mm=3809.5							-50cm
;PhaseThree_TurnDistShort:		DW	4071	;4.8m/1.05mm=4571.43, call 4571				-50cm
;PhaseThree_MaxDist:				DW	4262	;5.0m/1.05mm=4761.90, call 4762				-50cm
PhaseThree_EnableChecksDist:	DW	3810	;4.0m/1.05mm=3809.5
;PhaseThree_TurnDistShort:		DW	4571	;4.8m/1.05mm=4571.43, call 4571
;PhaseThree_MaxDist:				DW	4762	;5.0m/1.05mm=4761.90, call 4762

PhaseFive_EnableChecksDist:		DW	3810	;4.0m/1.05mm=3809.5							-50cm
;PhaseFive_TurnDistShort:		DW	4071	;4.8m/1.05mm=4571.43, call 4571				-50cm
;PhaseFive_MaxDist:				DW	4262	;5.0m/1.05mm=4761.90, call 4762				-50cm
;PhaseFive_EnableChecksDist:		DW	3810	;4.0m/1.05mm=3809.5
;PhaseFive_TurnDistShort:		DW	4571	;4.8m/1.05mm=4571.43, call 4571
PhaseFive_TurnDistShort:		DW	4711	;4.8m/1.05mm=4571.43, call 4571				+150
PhaseFive_MaxDist:				DW	4762	;5.0m/1.05mm=4761.90, call 4762

PhaseSeven_EnableChecksDist:	DW	2850	;3.5m/1.05mm=3333, call it 3350				-50cm
PhaseSeven_TurnDistShort:		DW	3310	;4.0m/1.05mm=3809.5							-50cm
PhaseSeven_MaxDist:				DW	3500	;4.2m/1.05mm=4000							-50cm
;PhaseSeven_EnableChecksDist:	DW	3350	;3.5m/1.05mm=3333, call it 3350
;PhaseSeven_TurnDistShort:		DW	3810	;4.0m/1.05mm=3809.5
;PhaseSeven_MaxDist:				DW	4000	;4.2m/1.05mm=4000

;Sonar values, all actual valuies in mm
PhaseOne_WallDistRight:		DW	750
PhaseOne_WallDistCutoff:	DW	400

PhaseThree_WallDistRight:	DW	200
PhaseThree_WallDistCutoff:	DW	250			;12.5cm doubled

PhaseFive_WallDistLeft:		DW	300
PhaseFive_WallDistCutoff:	DW	320			;16cm doubled

PhaseSeven_WallDistLeft:	DW	300
PhaseSeven_WallDistCutoff:	DW	320			;16cm doubled

PhaseFour_LastChanceCutoff:		DW	200
PhaseEight_LastChanceCutoff:	DW	400

;Working values for the common code segments
Cur_MinTurnDist:			DW  0
Cur_MaxTurnDist:			DW	0
Cur_WallCutoff:				DW	0

CurPOS_TurnCheck:			DW	0
CurPOS_WallDist:			DW	0
Current_LastChanceCutoff:	DW	0

WallDistGood:		DW	0
WallDistMax:		DW	0
WallDistMin:		DW	0
Can_Trans:			DW	0
BotNotStraight:		DW	0

;Wall distance for averagers
CurWallDist:				DW	0
AVGWallDist:				DW	0
Quad_AVGWallDist:			DW	0
LastWallDistAVG:			DW	0
LastWallDistCount:			DW	0
WallDist1:					DW	0
WallDist2:					DW	0
WallDist3:					DW	0
WallDist4:					DW	0
CurWallDistAhead:			DW	0

NewTFAngle:  				DW 0     ; stores turn angle
TFAngle:  					DW 0     ; stores turn angle
TFDVel:   					DW 0     ; temporarily stores velocity
Temp2:						DW	0


;Check values
XPOS_Check:					DW	0
YPOS_Check:					DW	0
Check1Hex:					DW	&HCEC1
Check2Hex:					DW	&HCEC2
Check3Hex:					DW	&HCEC3
Check4Hex:					DW	&HCEC4
Check5Hex:					DW	&HCEC5
Check6Hex:					DW	&HCEC6
Check7Hex:					DW	&HCEC7
Check8Hex:					DW	&HCEC8

NewPhase:					DW	0		;Check variable for going into a new phase from the phase checks, else call-return errors
NumNullVals:				DW	0
NULLDistanceValue:			DW	&H7FFF
OldDTheta:					DW	0
PhaseNum:					DW	0
; Control code.  If called repeatedly, this code will attempt
; to control the robot to face the angle specified in DTheta
; and match the speed specified in DVel
DTheta:    		DW 	0
DVel:      		DW 	0
ControlMovement:
	LOADI  50          ; used for the CapValue subroutine
	STORE  MaxVal
	CALL   GetThetaErr ; get the heading error
	; A simple way to get a decent velocity value
	; for turning is to multiply the angular error by 4
	; and add ~50.
	SHIFT  2
	STORE  CMAErr      ; hold temporarily
	SHIFT  2           ; multiply by another 4
	CALL   CapValue    ; get a +/- max of 50
	ADD    CMAErr
	STORE  CMAErr      ; now contains a desired differential

	
	; For this basic control method, simply take the
	; desired forward velocity and add the differential
	; velocity for each wheel when turning is needed.
	LOADI  510
	STORE  MaxVal
	LOAD   DVel
	CALL   CapValue    ; ensure velocity is valid
	STORE  DVel        ; overwrite any invalid input
	ADD    CMAErr
	CALL   CapValue    ; ensure velocity is valid
	STORE  CMAR
	LOAD   CMAErr
	CALL   Neg         ; left wheel gets negative differential
	ADD    DVel
	CALL   CapValue
	STORE  CMAL

	; ensure enough differential is applied
	LOAD   CMAErr
	SHIFT  1           ; double the differential
	STORE  CMAErr
	LOAD   CMAR
	SUB    CMAL        ; calculate the actual differential
	SUB    CMAErr      ; should be 0 if nothing got capped
	JZERO  CMADone
	; re-apply any missing differential
	STORE  CMAErr      ; the missing part
	ADD    CMAL
	CALL   CapValue
	STORE  CMAL
	LOAD   CMAR
	SUB    CMAErr
	CALL   CapValue
	STORE  CMAR

CMADone:
	LOAD   CMAL
	OUT    LVELCMD
	LOAD   CMAR
	OUT    RVELCMD

	RETURN
	CMAErr: DW 0       ; holds angle error velocity
	CMAL:    DW 0      ; holds temp left velocity
	CMAR:    DW 0      ; holds temp right velocity

; Returns the current angular error wrapped to +/-180
GetThetaErr:
	; convenient way to get angle error in +/-180 range is
	; ((error + 180) % 360 ) - 180
	IN     THETA
	SUB    DTheta      ; actual - desired angle
	CALL   Neg         ; desired - actual angle
	ADDI   180
	CALL   Mod360
	ADDI   -180
	RETURN

; caps a value to +/-MaxVal
CapValue:
	SUB     MaxVal
	JPOS    CapVelHigh
	ADD     MaxVal
	ADD     MaxVal
	JNEG    CapVelLow
	SUB     MaxVal
	RETURN
CapVelHigh:
	LOAD    MaxVal
	RETURN
CapVelLow:
	LOAD    MaxVal
	CALL    Neg
	RETURN
	MaxVal: DW 510


;*******************************************************************************
; Mod360: modulo 360
; Returns AC%360 in AC
; Written by Kevin Johnson.  No licence or copyright applied.
;*******************************************************************************
Mod360:
	; easy modulo: subtract 360 until negative then add 360 until not negative
	JNEG   M360N
	ADDI   -360
	JUMP   Mod360
M360N:
	ADDI   360
	JNEG   M360N
	RETURN

;*******************************************************************************
; Abs: 2's complement absolute value
; Returns abs(AC) in AC
; Neg: 2's complement negation
; Returns -AC in AC
; Written by Kevin Johnson.  No licence or copyright applied.
;*******************************************************************************
Abs:
	JPOS   Abs_r
Neg:
	XOR    NegOne       ; Flip all bits
	ADDI   1            ; Add one (i.e. negate number)
Abs_r:
	RETURN

;******************************************************************************;
; Atan2: 4-quadrant arctangent calculation                                     ;
; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ;
; Original code by Team AKKA, Spring 2015.                                     ;
; Based on methods by Richard Lyons                                            ;
; Code updated by Kevin Johnson to use software mult and div                   ;
; No license or copyright applied.                                             ;
; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ;
; To use: store dX and dY in global variables AtanX and AtanY.                 ;
; Call Atan2                                                                   ;
; Result (angle [0,359]) is returned in AC                                     ;
; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ;
; Requires additional subroutines:                                             ;
; - Mult16s: 16x16->32bit signed multiplication                                ;
; - Div16s: 16/16->16R16 signed division                                       ;
; - Abs: Absolute value                                                        ;
; Requires additional constants:                                               ;
; - One:     DW 1                                                              ;
; - NegOne:  DW 0                                                              ;
; - LowByte: DW &HFF                                                           ;
;******************************************************************************;
Atan2:
	LOAD   AtanY
	CALL   Abs          ; abs(y)
	STORE  AtanT
	LOAD   AtanX        ; abs(x)
	CALL   Abs
	SUB    AtanT        ; abs(x) - abs(y)
	JNEG   A2_sw        ; if abs(y) > abs(x), switch arguments.
	LOAD   AtanX        ; Octants 1, 4, 5, 8
	JNEG   A2_R3
	CALL   A2_calc      ; Octants 1, 8
	JNEG   A2_R1n
	RETURN              ; Return raw value if in octant 1
A2_R1n: ; region 1 negative
	ADDI   360          ; Add 360 if we are in octant 8
	RETURN
A2_R3: ; region 3
	CALL   A2_calc      ; Octants 4, 5            
	ADDI   180          ; theta' = theta + 180
	RETURN
A2_sw: ; switch arguments; octants 2, 3, 6, 7 
	LOAD   AtanY        ; Swap input arguments
	STORE  AtanT
	LOAD   AtanX
	STORE  AtanY
	LOAD   AtanT
	STORE  AtanX
	JPOS   A2_R2        ; If Y positive, octants 2,3
	CALL   A2_calc      ; else octants 6, 7
	CALL   Neg          ; Negatge the number
	ADDI   270          ; theta' = 270 - theta
	RETURN
A2_R2: ; region 2
	CALL   A2_calc      ; Octants 2, 3
	CALL   Neg          ; negate the angle
	ADDI   90           ; theta' = 90 - theta
	RETURN
A2_calc:
	; calculates R/(1 + 0.28125*R^2)
	LOAD   AtanY
	STORE  d16sN        ; Y in numerator
	LOAD   AtanX
	STORE  d16sD        ; X in denominator
	CALL   A2_div       ; divide
	LOAD   dres16sQ     ; get the quotient (remainder ignored)
	STORE  AtanRatio
	STORE  m16sA
	STORE  m16sB
	CALL   A2_mult      ; X^2
	STORE  m16sA
	LOAD   A2c
	STORE  m16sB
	CALL   A2_mult
	ADDI   256          ; 256/256+0.28125X^2
	STORE  d16sD
	LOAD   AtanRatio
	STORE  d16sN        ; Ratio in numerator
	CALL   A2_div       ; divide
	LOAD   dres16sQ     ; get the quotient (remainder ignored)
	STORE  m16sA        ; <= result in radians
	LOAD   A2cd         ; degree conversion factor
	STORE  m16sB
	CALL   A2_mult      ; convert to degrees
	STORE  AtanT
	SHIFT  -7           ; check 7th bit
	AND    One
	JZERO  A2_rdwn      ; round down
	LOAD   AtanT
	SHIFT  -8
	ADDI   1            ; round up
	RETURN
A2_rdwn:
	LOAD   AtanT
	SHIFT  -8           ; round down
	RETURN
A2_mult: ; multiply, and return bits 23..8 of result
	CALL   Mult16s
	LOAD   mres16sH
	SHIFT  8            ; move high word of result up 8 bits
	STORE  mres16sH
	LOAD   mres16sL
	SHIFT  -8           ; move low word of result down 8 bits
	AND    LowByte
	OR     mres16sH     ; combine high and low words of result
	RETURN
A2_div: ; 16-bit division scaled by 256, minimizing error
	LOADI  9            ; loop 8 times (256 = 2^8)
	STORE  AtanT
A2_DL:
	LOAD   AtanT
	ADDI   -1
	JPOS   A2_DN        ; not done; continue shifting
	CALL   Div16s       ; do the standard division
	RETURN
A2_DN:
	STORE  AtanT
	LOAD   d16sN        ; start by trying to scale the numerator
	SHIFT  1
	XOR    d16sN        ; if the sign changed,
	JNEG   A2_DD        ; switch to scaling the denominator
	XOR    d16sN        ; get back shifted version
	STORE  d16sN
	JUMP   A2_DL
A2_DD:
	LOAD   d16sD
	SHIFT  -1           ; have to scale denominator
	STORE  d16sD
	JUMP   A2_DL
AtanX:      DW 0
AtanY:      DW 0
AtanRatio:  DW 0        ; =y/x
AtanT:      DW 0        ; temporary value
A2c:        DW 72       ; 72/256=0.28125, with 8 fractional bits
A2cd:       DW 14668    ; = 180/pi with 8 fractional bits

;*******************************************************************************
; Mult16s:  16x16 -> 32-bit signed multiplication
; Based on Booth's algorithm.
; Written by Kevin Johnson.  No licence or copyright applied.
; Warning: does not work with factor B = -32768 (most-negative number).
; To use:
; - Store factors in m16sA and m16sB.
; - Call Mult16s
; - Result is stored in mres16sH and mres16sL (high and low words).
;*******************************************************************************
Mult16s:
	LOADI  0
	STORE  m16sc        ; clear carry
	STORE  mres16sH     ; clear result
	LOADI  16           ; load 16 to counter
Mult16s_loop:
	STORE  mcnt16s      
	LOAD   m16sc        ; check the carry (from previous iteration)
	JZERO  Mult16s_noc  ; if no carry, move on
	LOAD   mres16sH     ; if a carry, 
	ADD    m16sA        ;  add multiplicand to result H
	STORE  mres16sH
Mult16s_noc: ; no carry
	LOAD   m16sB
	AND    One          ; check bit 0 of multiplier
	STORE  m16sc        ; save as next carry
	JZERO  Mult16s_sh   ; if no carry, move on to shift
	LOAD   mres16sH     ; if bit 0 set,
	SUB    m16sA        ;  subtract multiplicand from result H
	STORE  mres16sH
Mult16s_sh:
	LOAD   m16sB
	SHIFT  -1           ; shift result L >>1
	AND    c7FFF        ; clear msb
	STORE  m16sB
	LOAD   mres16sH     ; load result H
	SHIFT  15           ; move lsb to msb
	OR     m16sB
	STORE  m16sB        ; result L now includes carry out from H
	LOAD   mres16sH
	SHIFT  -1
	STORE  mres16sH     ; shift result H >>1
	LOAD   mcnt16s
	ADDI   -1           ; check counter
	JPOS   Mult16s_loop ; need to iterate 16 times
	LOAD   m16sB
	STORE  mres16sL     ; multiplier and result L shared a word
	RETURN              ; Done
c7FFF: DW &H7FFF
m16sA: DW 0 ; multiplicand
m16sB: DW 0 ; multipler
m16sc: DW 0 ; carry
mcnt16s: DW 0 ; counter
mres16sL: DW 0 ; result low
mres16sH: DW 0 ; result high

;*******************************************************************************
; Div16s:  16/16 -> 16 R16 signed division
; Written by Kevin Johnson.  No licence or copyright applied.
; Warning: results undefined if denominator = 0.
; To use:
; - Store numerator in d16sN and denominator in d16sD.
; - Call Div16s
; - Result is stored in dres16sQ and dres16sR (quotient and remainder).
; Requires Abs subroutine
;*******************************************************************************
Div16s:
	LOADI  0
	STORE  dres16sR     ; clear remainder result
	STORE  d16sC1       ; clear carry
	LOAD   d16sN
	XOR    d16sD
	STORE  d16sS        ; sign determination = N XOR D
	LOADI  17
	STORE  d16sT        ; preload counter with 17 (16+1)
	LOAD   d16sD
	CALL   Abs          ; take absolute value of denominator
	STORE  d16sD
	LOAD   d16sN
	CALL   Abs          ; take absolute value of numerator
	STORE  d16sN
Div16s_loop:
	LOAD   d16sN
	SHIFT  -15          ; get msb
	AND    One          ; only msb (because shift is arithmetic)
	STORE  d16sC2       ; store as carry
	LOAD   d16sN
	SHIFT  1            ; shift <<1
	OR     d16sC1       ; with carry
	STORE  d16sN
	LOAD   d16sT
	ADDI   -1           ; decrement counter
	JZERO  Div16s_sign  ; if finished looping, finalize result
	STORE  d16sT
	LOAD   dres16sR
	SHIFT  1            ; shift remainder
	OR     d16sC2       ; with carry from other shift
	SUB    d16sD        ; subtract denominator from remainder
	JNEG   Div16s_add   ; if negative, need to add it back
	STORE  dres16sR
	LOADI  1
	STORE  d16sC1       ; set carry
	JUMP   Div16s_loop
Div16s_add:
	ADD    d16sD        ; add denominator back in
	STORE  dres16sR
	LOADI  0
	STORE  d16sC1       ; clear carry
	JUMP   Div16s_loop
Div16s_sign:
	LOAD   d16sN
	STORE  dres16sQ     ; numerator was used to hold quotient result
	LOAD   d16sS        ; check the sign indicator
	JNEG   Div16s_neg
	RETURN
Div16s_neg:
	LOAD   dres16sQ     ; need to negate the result
	CALL   Neg
	STORE  dres16sQ
	RETURN	
d16sN: DW 0 ; numerator
d16sD: DW 0 ; denominator
d16sS: DW 0 ; sign value
d16sT: DW 0 ; temp counter
d16sC1: DW 0 ; carry value
d16sC2: DW 0 ; carry value
dres16sQ: DW 0 ; quotient result
dres16sR: DW 0 ; remainder result

;*******************************************************************************
; L2Estimate:  Pythagorean distance estimation
; Written by Kevin Johnson.  No licence or copyright applied.
; Warning: this is *not* an exact function.  I think it's most wrong
; on the axes, and maybe at 45 degrees.
; To use:
; - Store X and Y offset in L2X and L2Y.
; - Call L2Estimate
; - Result is returned in AC.
; Result will be in same units as inputs.
; Requires Abs and Mult16s subroutines.
;*******************************************************************************
L2Estimate:
	; take abs() of each value, and find the largest one
	LOAD   L2X
	CALL   Abs
	STORE  L2T1
	LOAD   L2Y
	CALL   Abs
	SUB    L2T1
	JNEG   GDSwap    ; swap if needed to get largest value in X
	ADD    L2T1
CalcDist:
	; Calculation is max(X,Y)*0.961+min(X,Y)*0.406
	STORE  m16sa
	LOADI  246       ; max * 246
	STORE  m16sB
	CALL   Mult16s
	LOAD   mres16sH
	SHIFT  8
	STORE  L2T2
	LOAD   mres16sL
	SHIFT  -8        ; / 256
	AND    LowByte
	OR     L2T2
	STORE  L2T3
	LOAD   L2T1
	STORE  m16sa
	LOADI  104       ; min * 104
	STORE  m16sB
	CALL   Mult16s
	LOAD   mres16sH
	SHIFT  8
	STORE  L2T2
	LOAD   mres16sL
	SHIFT  -8        ; / 256
	AND    LowByte
	OR     L2T2
	ADD    L2T3     ; sum
	RETURN
GDSwap: ; swaps the incoming X and Y
	ADD    L2T1
	STORE  L2T2
	LOAD   L2T1
	STORE  L2T3
	LOAD   L2T2
	STORE  L2T1
	LOAD   L2T3
	JUMP   CalcDist
L2X:  DW 0
L2Y:  DW 0
L2T1: DW 0
L2T2: DW 0
L2T3: DW 0


; Subroutine to wait (block) for 1 second
Wait1:
	OUT    TIMER
Wloop1:
	IN     TIMER
	OUT    XLEDS       ; User-feedback that a pause is occurring.
	ADDI   -10         ; 1 second at 10Hz.
	JNEG   Wloop1
	RETURN
; Subroutine to wait (block) for 1 second

WaitP1:
	OUT    TIMER
WloopP1:
	IN     TIMER
	OUT    XLEDS      	; User-feedback that a pause is occurring.
	ADDI   -1         	; .1 second at 10Hz.
	JNEG   WloopP1
	RETURN
; Subroutine to wait (block) for 1 second

WaitP5:
	OUT    TIMER
WloopP5:
	IN     TIMER
	OUT    XLEDS       ; User-feedback that a pause is occurring.
	ADDI   -5         ; .5 second at 10Hz.
	JNEG   WloopP5
	RETURN

; This subroutine will get the battery voltage,
; and stop program execution if it is too low.
; SetupI2C must be executed prior to this.
BattCheck:
	CALL   GetBattLvl
	JZERO  BattCheck   ; A/D hasn't had time to initialize
	SUB    MinBatt
	JNEG   DeadBatt
	ADD    MinBatt     ; get original value back
	RETURN
; If the battery is too low, we want to make
; sure that the user realizes it...
DeadBatt:
	LOADI  &H20
	OUT    BEEP        ; start beep sound
	CALL   GetBattLvl  ; get the battery level
	OUT    SSEG1       ; display it everywhere
	OUT    SSEG2
	OUT    LCD
	LOAD   Zero
	ADDI   -1          ; 0xFFFF
	OUT    LEDS        ; all LEDs on
	OUT    XLEDS
	CALL   Wait1       ; 1 second
	LOADI  &H140       ; short, high-pitched beep
	OUT    BEEP        ; stop beeping
	LOAD   Zero
	OUT    LEDS        ; LEDs off
	OUT    XLEDS
	CALL   Wait1       ; 1 second
	JUMP   DeadBatt    ; repeat forever
	
; Subroutine to read the A/D (battery voltage)
; Assumes that SetupI2C has been run
GetBattLvl:
	LOAD   I2CRCmd     ; 0x0190 (write 0B, read 1B, addr 0x90)
	OUT    I2C_CMD     ; to I2C_CMD
	OUT    I2C_RDY     ; start the communication
	CALL   BlockI2C    ; wait for it to finish
	IN     I2C_DATA    ; get the returned data
	RETURN

; Subroutine to configure the I2C for reading batt voltage
; Only needs to be done once after each reset.
SetupI2C:
	CALL   BlockI2C    ; wait for idle
	LOAD   I2CWCmd     ; 0x1190 (write 1B, read 1B, addr 0x90)
	OUT    I2C_CMD     ; to I2C_CMD register
	LOAD   Zero        ; 0x0000 (A/D port 0, no increment)
	OUT    I2C_DATA    ; to I2C_DATA register
	OUT    I2C_RDY     ; start the communication
	CALL   BlockI2C    ; wait for it to finish
	RETURN
	
; Subroutine to block until I2C device is idle
BlockI2C:
	LOAD   Zero
	STORE  Temp        ; Used to check for timeout
BI2CL:
	LOAD   Temp
	ADDI   1           ; this will result in ~0.1s timeout
	STORE  Temp
	JZERO  I2CError    ; Timeout occurred; error
	IN     I2C_RDY     ; Read busy signal
	JPOS   BI2CL       ; If not 0, try again
	RETURN             ; Else return
I2CError:
	LOAD   Zero
	ADDI   &H12C       ; "I2C"
	OUT    SSEG1
	OUT    SSEG2       ; display error message
	JUMP   I2CError

;***************************************************************
;* Variables
;***************************************************************
Temp:     DW 0 ; "Temp" is not a great name, but can be useful

;***************************************************************
;* Constants
;* (though there is nothing stopping you from writing to these)
;***************************************************************
NegOne:   	DW	-1
Zero:     	DW	0
One:      	DW	1
Two:      	DW	2
Three:    	DW	3
Four:     	DW	4
Five:     	DW	5
Six:      	DW	6
Seven:    	DW	7
Eight:    	DW	8
Nine:     	DW 9
Ten:      	DW 10

; Some bit masks.
; Masks of multiple bits can be constructed by ORing these
; 1-bit masks together.
Mask0:    DW &B00000001
Mask1:    DW &B00000010
Mask2:    DW &B00000100
Mask3:    DW &B00001000
Mask4:    DW &B00010000
Mask5:    DW &B00100000
Mask6:    DW &B01000000
Mask7:    DW &B10000000
LowByte:  DW &HFF      ; binary 00000000 1111111
LowNibl:  DW &HF       ; 0000 0000 0000 1111

; some useful movement values
OneMeter: DW 961       ; ~1m in 1.04mm units
HalfMeter: DW 481      ; ~0.5m in 1.04mm units
Ft2:      DW 586       ; ~2ft in 1.04mm units
Ft3:      DW 879
Ft4:      DW 1172
Deg90:    DW 90        ; 90 degrees in odometer units
Deg180:   DW 180       ; 180
Deg270:   DW 270       ; 270
Deg360:   DW 360       ; can never actually happen; for math only
FSlow:    DW 100       ; 100 is about the lowest velocity value that will move
RSlow:    DW -100
FMid:     DW 350       ; 350 is a medium speed
RMid:     DW -350
FFast:    DW 500       ; 500 is almost max speed (511 is max)
RFast:    DW -500

MinBatt:  DW 140       ; 14.0V - minimum safe battery voltage
I2CWCmd:  DW &H1190    ; write one i2c byte, read one byte, addr 0x90
I2CRCmd:  DW &H0190    ; write nothing, read one byte, addr 0x90

DataArray:
	DW 0
;***************************************************************
;* IO address space map
;***************************************************************
SWITCHES: EQU &H00  ; slide switches
LEDS:     EQU &H01  ; red LEDs
TIMER:    EQU &H02  ; timer, usually running at 10 Hz
XIO:      EQU &H03  ; pushbuttons and some misc. inputs
SSEG1:    EQU &H04  ; seven-segment display (4-digits only)
SSEG2:    EQU &H05  ; seven-segment display (4-digits only)
LCD:      EQU &H06  ; primitive 4-digit LCD display
XLEDS:    EQU &H07  ; Green LEDs (and Red LED16+17)
BEEP:     EQU &H0A  ; Control the beep
CTIMER:   EQU &H0C  ; Configurable timer for interrupts
LPOS:     EQU &H80  ; left wheel encoder position (read only)
LVEL:     EQU &H82  ; current left wheel velocity (read only)
LVELCMD:  EQU &H83  ; left wheel velocity command (write only)
RPOS:     EQU &H88  ; same values for right wheel...
RVEL:     EQU &H8A  ; ...
RVELCMD:  EQU &H8B  ; ...
I2C_CMD:  EQU &H90  ; I2C module's CMD register,
I2C_DATA: EQU &H91  ; ... DATA register,
I2C_RDY:  EQU &H92  ; ... and BUSY register
UART_DAT: EQU &H98  ; UART data
UART_RDY: EQU &H99  ; UART status
SONAR:    EQU &HA0  ; base address for more than 16 registers....
DIST0:    EQU &HA8  ; the eight sonar distance readings
DIST1:    EQU &HA9  ; ...
DIST2:    EQU &HAA  ; ...
DIST3:    EQU &HAB  ; ...
DIST4:    EQU &HAC  ; ...
DIST5:    EQU &HAD  ; ...
DIST6:    EQU &HAE  ; ...
DIST7:    EQU &HAF  ; ...
SONALARM: EQU &HB0  ; Write alarm distance; read alarm register
SONARINT: EQU &HB1  ; Write mask for sonar interrupts
SONAREN:  EQU &HB2  ; register to control which sonars are enabled
XPOS:     EQU &HC0  ; Current X-position (read only)
YPOS:     EQU &HC1  ; Y-position
THETA:    EQU &HC2  ; Current rotational position of robot (0-359)
RESETPOS: EQU &HC3  ; write anything here to reset odometry to 0
RIN:      EQU &HC8
LIN:      EQU &HC9
IR_HI:    EQU &HD0  ; read the high word of the IR receiver (OUT will clear both words)
IR_LO:    EQU &HD1  ; read the low word of the IR receiver (OUT will clear both words)