package test

import "core:c"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:math"
import "core:sys/windows"
import "core:time"
import "core:unicode"
import rl "vendor:raylib"
import "core:os"
import p_str "python_string_functions"
import p_list "python_list_functions"
import p_int "python_int_functions"
import p_float "python_float_functions"
import p_heap "python_heap_functions"
print :: fmt.println
printf :: fmt.printf

DEBUG_MODE :: true

main :: proc() {

    when DEBUG_MODE {
        // tracking allocator
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf(
                    "=== %v allocations not freed: context.allocator ===\n",
                    len(track.allocation_map),
                )
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf(
                    "=== %v incorrect frees: context.allocator ===\n",
                    len(track.bad_free_array),
                )
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }

        // tracking temp_allocator
        track_temp: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track_temp, context.temp_allocator)
        context.temp_allocator = mem.tracking_allocator(&track_temp)

        defer {
            if len(track_temp.allocation_map) > 0 {
                fmt.eprintf(
                    "=== %v allocations not freed: context.temp_allocator ===\n",
                    len(track_temp.allocation_map),
                )
                for _, entry in track_temp.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track_temp.bad_free_array) > 0 {
                fmt.eprintf(
                    "=== %v incorrect frees: context.temp_allocator ===\n",
                    len(track_temp.bad_free_array),
                )
                for entry in track_temp.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track_temp)
        }
    }

    // main work
    print("Hello from Odin!")
    windows.SetConsoleOutputCP(windows.CODEPAGE.UTF8)
    start: time.Time = time.now()

    // code goes here

    elapsed: time.Duration = time.since(start)
    print("Odin took:", elapsed)

    SCREENWIDTH  : i32 = 800
    SCREENHEIGHT : i32 = 800

    rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_MAXIMIZED})

    rl.InitWindow(SCREENWIDTH, SCREENHEIGHT, "Image Viewer")
    rl.SetTargetFPS(60)

    // maximize the window
    rl.MaximizeWindow()

    // loading the files
    files, names := get_png_files_and_names("assets/")
    current := 0

    // texture and scale ------------------------------------------------------
    texture := load_png(files[current])
    scale : f32 = 1.0

    img_w := f32(texture.width)
    img_h := f32(texture.height)
    screen_w := f32(rl.GetScreenWidth())
    screen_h := f32(rl.GetScreenHeight())

    scale = 1.0
    if img_w > screen_w || img_h > screen_h {
        scale_w := screen_w / img_w
        scale_h := screen_h / img_h
        scale = min(scale_w, scale_h)
    }
    // ------------------------------------------------------------------------
    // zoom speed
    zoom_speed : f32 = 0.05

    // offset for panning
    offset := rl.Vector2{0, 0}
    dragging := false
    prev_mouse := rl.Vector2{}

    // screen resizing
    prev_screen_w := f32(rl.GetScreenWidth())
    prev_screen_h := f32(rl.GetScreenHeight())

    // ---------------------------------------------------------------------------------------------------------
    // title buffer info
    
    title_buffer: [256]u8
    title := format_title(
        &title_buffer,
        names[current],
        current + 1,
        len(names),
        int(scale * 100),
    )
    rl.SetWindowTitle(title)
    // ---------------------------------------------------------------------------------------------------------

    // ---------------------------------------------------------------------------------------------------------
    // tooltip
    show_tooltip := true
    // ---------------------------------------------------------------------------------------------------------

    for !rl.WindowShouldClose() {
        
        // **GET INPUT** ------------------------------------------------------
        // pressing right
        if rl.IsKeyPressed(.RIGHT) {
            current = (current + 1) % len(files)
            rl.UnloadTexture(texture)
            texture = load_png(files[current])
            
            img_w := f32(texture.width)
            img_h := f32(texture.height)
            screen_w := f32(rl.GetScreenWidth())
            screen_h := f32(rl.GetScreenHeight())

            scale = shrink_to_fit(img_w, img_h, screen_w, screen_h)
            offset = rl.Vector2{0, 0}

            title := format_title(
                &title_buffer,
                names[current],
                current + 1,
                len(names),
                int(scale * 100),
            )
            rl.SetWindowTitle(title)
        }

        // pressing left
        if rl.IsKeyPressed(.LEFT) {
            current = (current - 1 + len(files)) % len(files)
            rl.UnloadTexture(texture)
            texture = load_png(files[current])

            img_w := f32(texture.width)
            img_h := f32(texture.height)
            screen_w := f32(rl.GetScreenWidth())
            screen_h := f32(rl.GetScreenHeight())

            scale = shrink_to_fit(img_w, img_h, screen_w, screen_h)
            offset = rl.Vector2{0, 0}

            title := format_title(
                &title_buffer,
                names[current],
                current + 1,
                len(names),
                int(scale * 100),
            )
            rl.SetWindowTitle(title)
        }

        // snapping size to 'full size' or 'shink to fit'
        if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyDown(.LEFT_ALT) && rl.IsKeyPressed(.KP_0) {
            scale = 1.0 // Show image at full size
            offset = rl.Vector2{0, 0}
            
            title := format_title(
                &title_buffer,
                names[current],
                current + 1,
                len(names),
                int(scale * 100),
            )
            rl.SetWindowTitle(title)

        } else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.KP_0) {
            img_w := f32(texture.width)
            img_h := f32(texture.height)
            screen_w := f32(rl.GetScreenWidth())
            screen_h := f32(rl.GetScreenHeight())

            // either `shink_to_fit()` if image is larger than screen, `expand_to_fit()` if image is smaller
            if img_w > screen_w || img_h > screen_h {
                scale = shrink_to_fit(img_w, img_h, screen_w, screen_h) // original!
            } else if img_w < screen_w || img_h < screen_h {
                scale = expand_to_fit(img_w, img_h, screen_w, screen_h)
            }
            
            offset = rl.Vector2{0, 0}
            
            title := format_title(
                &title_buffer,
                names[current],
                current + 1,
                len(names),
                int(scale * 100),
            )
            rl.SetWindowTitle(title)
        }

        // scrolling the mouse wheel
        wheel := rl.GetMouseWheelMove()
        if wheel > 0 {
            scale += zoom_speed
            if scale > 5.0 {
                scale = 5.0 // zoom upper bound
            }
            
            title := format_title(
                &title_buffer,
                names[current],
                current + 1,
                len(names),
                int(scale * 100),
            )
            rl.SetWindowTitle(title)

        } else if wheel < 0 {
            scale -= zoom_speed
            if scale < 0.1 {
                scale = 0.1 // zoom lower bound
            }
            
            title := format_title(
                &title_buffer,
                names[current],
                current + 1,
                len(names),
                int(scale * 100),
            )
            rl.SetWindowTitle(title)
        }

        // ---------------------------------------------------------------------------------------------------------
        // panning logic
        mouse := rl.GetMousePosition()
        screen_w = f32(rl.GetScreenWidth())
        screen_h = f32(rl.GetScreenHeight())

        img_w = f32(texture.width)
        img_h = f32(texture.height)
        scaled_w := img_w * scale
        scaled_h := img_h * scale


        img_rect := rl.Rectangle{
            x = screen_w / 2 - scaled_w / 2 + offset.x,
            y = screen_h / 2 - scaled_h / 2 + offset.y,
            width = scaled_w,
            height = scaled_h,
        }


        // Check if mouse is over image
        mouse_over_image := rl.CheckCollisionPointRec(mouse, img_rect)

        if mouse_over_image {
            if rl.IsMouseButtonPressed(.LEFT) {
                dragging = true
                prev_mouse = mouse
                rl.SetMouseCursor(.RESIZE_ALL) // arrow pointing up, down, left and right
            } else if !dragging {
                rl.SetMouseCursor(.POINTING_HAND) // pointing hand
            }
        } else {
            rl.SetMouseCursor(.DEFAULT) // arrow
        }

        if dragging {
            if rl.IsMouseButtonDown(.LEFT) {
                delta := rl.Vector2{mouse.x - prev_mouse.x, mouse.y - prev_mouse.y}
                offset.x += delta.x
                offset.y += delta.y
                prev_mouse = mouse
            } else {
                dragging = false
            }
        }

        // clamp offset
        max_offset_x := max(0, (scaled_w - screen_w) / 2)
        max_offset_y := max(0, (scaled_h - screen_h) / 2)

        offset.x = clamp(offset.x, -max_offset_x, max_offset_x)
        offset.y = clamp(offset.y, -max_offset_y, max_offset_y)


        // 'Alt + Enter' to maximize and restore windows
        if rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT) {
            if rl.IsKeyPressed(.ENTER) {
                if (rl.IsWindowState({.WINDOW_MAXIMIZED})) {
                    rl.RestoreWindow()
                } else {
                    rl.MaximizeWindow()
                }
            }
        }

        // 'z + up arrow and down arrow' for quick zooming
        if rl.IsKeyDown(.Z) && rl.IsKeyPressed(.UP) {
            if scale + 1.0 <= 5.0 {
                scale = scale + 1.0
            } else {
                scale = 5.0
            }

            title := format_title(
                &title_buffer,
                names[current],
                current + 1,
                len(names),
                int(scale * 100),
            )
            rl.SetWindowTitle(title)
            
        } else if rl.IsKeyDown(.Z) && rl.IsKeyPressed(.DOWN) {
            if scale - 1.0 >= 0.1 {
                scale = scale - 1.0
            } else {
                scale = 0.1
            }

            title := format_title(
                &title_buffer,
                names[current],
                current + 1,
                len(names),
                int(scale * 100),
            )
            rl.SetWindowTitle(title)
        }
        // ---------------------------------------------------------------------------------------------------------

        // ---------------------------------------------------------------------------------------------------------
        //tooltip
        if rl.IsKeyPressed(.T) {
            show_tooltip = !show_tooltip
        }
        // ---------------------------------------------------------------------------------------------------------

        // **UPDATE** ---------------------------------------------------------
        screen_w := f32(rl.GetScreenWidth())
        screen_h := f32(rl.GetScreenHeight())

        if screen_w != prev_screen_w || screen_h != prev_screen_h {
            img_w := f32(texture.width)
            img_h := f32(texture.height)
            scale = shrink_to_fit(img_w, img_h, screen_w, screen_h)
            offset = rl.Vector2{0, 0} // Optional: reset panning
            prev_screen_w = screen_w
            prev_screen_h = screen_h
        }

        img_w := f32(texture.width)
        img_h := f32(texture.height)

        pos_x := screen_w / 2 - scaled_w / 2 + offset.x
        pos_y := screen_h / 2 - scaled_h / 2 + offset.y

        // tooltip
        tooltip_text : cstring = ""
        if show_tooltip {
            tooltip_text = "Left Arrow/Right Arrow to change image | Mouse wheel to zoom | Ctrl+Alt+0 for original size | Ctrl+0 to fit screen | T to toggle tooltip | Alt+Enter to toggle maximized | Z + Up/Down"
        } else {
            tooltip_text = "T to toggle tooltip"
        }


        // **DRAWING** --------------------------------------------------------
        rl.BeginDrawing()
        
        rl.ClearBackground(rl.RAYWHITE)
        rl.DrawTextureEx(texture, rl.Vector2{pos_x, pos_y}, 0.0, scale, rl.WHITE)

        // tooltip at bottom
        if show_tooltip {
            rl.DrawRectangle(0, i32(screen_h - 30), i32(screen_w), 30, rl.GRAY)
        } else {
            rl.DrawRectangle(0, i32(screen_h - 30), 220, 30, rl.GRAY)
        }
        rl.DrawText(tooltip_text, 10, i32(screen_h - 25), 20, rl.WHITE)

        // draw FPS last
        // rl.DrawText(rl.TextFormat("FPS: %d", rl.GetFPS()), 25, 25, 20, rl.BLACK)
        
        rl.EndDrawing()
    }

    rl.UnloadTexture(texture)
    rl.CloseWindow()

    free_all(context.temp_allocator)
}


load_png :: proc(path: string) -> rl.Texture2D {
    image := rl.LoadImage(strings.clone_to_cstring(path, context.temp_allocator))
    texture := rl.LoadTextureFromImage(image)
    rl.UnloadImage(image)
    return texture
}

get_png_files_and_names :: proc(dir: string) -> ([]string, []string) {
    dir_handle, err_00 := os.open(dir, os.O_RDONLY, 0)
    if err_00 != os.ERROR_NONE {
        panic("Error getting handle from directory.")
    }

    entries, err_01 := os.read_dir(dir_handle, 1024, context.temp_allocator)
    if err_01 != os.ERROR_NONE {
        os.close(dir_handle)
        panic("Error getting entries from directory.")
    }

    images := make([dynamic]string, context.temp_allocator)
    names  := make([dynamic]string, context.temp_allocator)

    for entry in entries {
        if entry.is_dir == false {
            if p_str.endswith(entry.name, ".png")  || 
               p_str.endswith(entry.name, ".PNG")  || 
               p_str.endswith(entry.name, ".jpg")  || 
               p_str.endswith(entry.name, ".jpeg") {
                append(&images, entry.fullpath)
                append(&names, entry.name)
            }
        }
    }

    return images[:], names[:]
}

shrink_to_fit :: proc(img_w, img_h, screen_w, screen_h: f32) -> f32 {
    if img_w > screen_w || img_h > screen_h {
        scale_w := screen_w / img_w
        scale_h := screen_h / img_h
        return min(scale_w, scale_h)
    }
    return 1.0
}

expand_to_fit :: proc(img_w, img_h, screen_w, screen_h: f32) -> f32 {
    if img_w < screen_w || img_h < screen_h {
        scale_w := screen_w / img_w
        scale_h := screen_h / img_h
        return min(scale_w, scale_h)
    }
    return 1.0
}

format_title :: proc(buffer: ^[256]u8, name: string, index: int, total: int, zoom: int) -> cstring {
    // clear buffer
    buffer^ = {}
    
    // ensure final cstring is less than 256 characters long
    _name := name[:]
    if len(name) > 100 {_name = name[:100]} // just chop it off

    // create new string with updated info
    val := fmt.bprintf(
        buffer[:],
        "Image Viewer | %s | (%d/%d) | Zoom: %d%%",
        _name,
        index,
        total,
        zoom,
    )

    // change to cstring and return it
    return cstring(raw_data(val))
}
