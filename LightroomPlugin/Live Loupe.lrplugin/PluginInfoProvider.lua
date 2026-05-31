-- Live Loupe
-- Author: Artsiom Shabanau  - The Capture Crafter
-- License: MIT
--
-- Provides the section shown in Lightroom's File > Plug-in Manager.

local LrView = import 'LrView'

return {
  sectionsForTopOfDialog = function(viewFactory, _)
    return {
      {
        title = 'Live Loupe',

        viewFactory:row {
          viewFactory:static_text {
            title = 'Local Lightroom previews on your iPhone over Wi-Fi.',
            fill_horizontal = 1,
          },
        },

        viewFactory:row {
          viewFactory:static_text {
            title = 'Author:',
            width = 70,
          },
          viewFactory:static_text {
            title = 'Artsiom Shabanau  - The Capture Crafter',
            fill_horizontal = 1,
          },
        },

        viewFactory:row {
          viewFactory:static_text {
            title = 'License:',
            width = 70,
          },
          viewFactory:static_text {
            title = 'MIT',
            fill_horizontal = 1,
          },
        },
      },
    }
  end,
}
