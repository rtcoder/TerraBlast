class_name MatchState
extends "res://scripts/core/turns/turn_controller.gd"

var status := "playing"
var time_remaining := 45.0
var winner_team := 0
var winner_player := ""
var inventory: Dictionary = {}
var revision := 0
var generation := 0
