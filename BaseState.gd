extends Node
class_name BaseState

var machine: GameStateMachine

func enter(_data := {}): 
	pass

func exit():
	pass

func handle_input(_event: InputEvent):
	pass

func update(_delta: float):
	pass
