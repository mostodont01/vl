// Include in node headers that draw an app widget. Put drawWidget()
// overrides inside #ifdef VL_GUI, so the node also builds without a GUI.
#pragma once

#ifdef VL_GUI
#include "imgui.h"
#endif
