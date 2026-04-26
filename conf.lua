function love.conf(t)
    t.identity         = nil        -- The name of the save directory (string)
    t.version          = "12.0"     -- The LÖVE version this game was made for (string)
    t.console          = true       -- Attach a console (boolean, Windows only)

    t.window.title     = "Nes Emulator" -- The window title (string)
    t.window.icon      = nil        -- Filepath to an image to use as the window's icon (string)
    t.window.width     = 1100        -- The window width (number) 1920 960
    t.window.height    = 1000        -- The window height (number) 1080 540

    t.window.vsync     = true      -- Enable vertical sync (boolean)
    t.window.renderers = {"vulkan"}
    t.window.resizable = true       -- Window can be Resized
end
