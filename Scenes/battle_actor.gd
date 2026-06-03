extends StaticBody3D
var Health : int = 1
var Action : int = 1
var Spark : int = 1
var Atack : int = 1
var Defense : int = 1
var speed : int = 1
var Luck : int = 1
var Resilience : int = 1
var SP : int = 1
@onready var progress_bar: ProgressBar = $Sprite3D/SubViewport/ProgressBar

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
