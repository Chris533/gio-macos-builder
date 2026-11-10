package main

import (
	"os"

	"gioui.org/app"
	"gioui.org/op"
	"gioui.org/x/explorer"
)

func main() {
	go func() {
		var w app.Window
		w.Option(app.Title("SmokeGio"))
		exp := explorer.NewExplorer(&w)
		var ops op.Ops
		for {
			e := w.Event()
			exp.ListenEvents(e)
			switch e := e.(type) {
			case app.DestroyEvent:
				os.Exit(0)
			case app.FrameEvent:
				gtx := app.NewContext(&ops, e)
				e.Frame(gtx.Ops)
			}
		}
	}()
	app.Main()
}
