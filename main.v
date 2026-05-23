module main

import os
import time
import json
import gg

#flag darwin -L/opt/homebrew/lib
#flag darwin -L/usr/local/lib

pub struct Entry {
pub mut:
	id      string
	title   string
	content string
	date    string
	mood    string
	tags    []string
}

enum Mode {
	view
	create
	edit
}

struct TextInput {
pub mut:
	text       string
	is_focused bool
	cursor_pos int
}

struct Settings {
mut:
	is_dark_mode bool
	win_width    int
	win_height   int
}

struct Theme {
	bg_base       gg.Color
	bg_sidebar    gg.Color
	border        gg.Color
	text_primary  gg.Color
	text_sec      gg.Color
	accent        gg.Color
	input_bg      gg.Color
	card_bg       gg.Color
	card_sel      gg.Color
}

fn get_theme(is_dark bool) Theme {
	if is_dark {
		return Theme{
			bg_base:      gg.rgb(20, 20, 25)
			bg_sidebar:   gg.rgb(30, 30, 40)
			border:       gg.rgb(50, 50, 60)
			text_primary: gg.rgb(240, 240, 245)
			text_sec:     gg.rgb(160, 160, 170)
			accent:       gg.rgb(139, 92, 246)
			input_bg:     gg.rgb(45, 45, 55)
			card_bg:      gg.rgb(35, 35, 45)
			card_sel:     gg.rgb(55, 55, 70)
		}
	} else {
		return Theme{
			bg_base:      gg.rgb(245, 245, 247)
			bg_sidebar:   gg.rgb(255, 255, 255)
			border:       gg.rgb(220, 220, 225)
			text_primary: gg.rgb(30, 30, 35)
			text_sec:     gg.rgb(100, 100, 110)
			accent:       gg.rgb(109, 40, 217)
			input_bg:     gg.rgb(235, 235, 240)
			card_bg:      gg.rgb(240, 240, 245)
			card_sel:     gg.rgb(220, 220, 235)
		}
	}
}

@[heap]
struct App {
pub mut:
	ctx            &gg.Context = unsafe { nil }
	entries        []Entry
	selected_index int = -1
	mode           Mode = .view

	// Scroll positions
	list_scroll_y    int
	content_scroll_y int

	// Form inputs
	title_input     TextInput
	content_input   TextInput
	tags_input      TextInput
	mood_input      TextInput
	search_input    TextInput
	date_from_input TextInput
	date_to_input   TextInput

	// Filters
	filter_mood   string = 'All'
	filter_date   string = 'All Time'

	// Theme
	is_dark_mode  bool = true

	// Layout
	win_width     int = 800
	win_height    int = 600
	sidebar_width int = 250

	// Hover states
	hover_new         bool
	hover_save        bool
	hover_cancel      bool
	hover_edit        bool
	hover_delete      bool
	hover_theme       bool
	hover_filter_mood bool
	hover_filter_date bool
	hover_moods       []bool
	hover_exit        bool
	
	// Cursor blinking
	cursor_ticks int
}

fn (entry Entry) matches_search(query string) bool {
	q := query.trim_space().to_lower()
	if q == '' {
		return true
	}
	if entry.title.to_lower().contains(q) {
		return true
	}
	if entry.content.to_lower().contains(q) {
		return true
	}
	for tag in entry.tags {
		if tag.to_lower().contains(q) {
			return true
		}
	}
	return false
}

fn (entry Entry) matches_date_filter(filter string, from_val string, to_val string) bool {
	if filter == 'All Time' {
		return true
	}
	if filter == 'Custom Range' {
		mut matches := true
		f := from_val.trim_space()
		t := to_val.trim_space()
		if f != '' {
			matches = matches && entry.date >= f
		}
		if t != '' {
			matches = matches && entry.date <= t
		}
		return matches
	}
	today := time.now()
	today_str := today.custom_format('YYYY-MM-DD')
	if filter == 'Today' {
		return entry.date == today_str
	}
	if filter == 'This Month' {
		if entry.date.len >= 7 && today_str.len >= 7 {
			return entry.date[0..7] == today_str[0..7]
		}
	}
	if filter == 'This Year' {
		if entry.date.len >= 4 && today_str.len >= 4 {
			return entry.date[0..4] == today_str[0..4]
		}
	}
	if filter == 'This Week' {
		entry_t := time.parse('${entry.date} 00:00:00') or { return false }
		diff := today.unix() - entry_t.unix()
		return diff >= 0 && diff <= 7 * 24 * 3600
	}
	return true
}

fn write_entries_to_file(entries []Entry) {
	data := json.encode(entries)
	os.write_file('entries.json', data) or {}
}

fn read_entries_from_file() []Entry {
	if !os.exists('entries.json') {
		return []Entry{}
	}
	content := os.read_file('entries.json') or { return []Entry{} }
	if content.trim_space() == '' {
		return []Entry{}
	}
	entries := json.decode([]Entry, content) or { return []Entry{} }
	return entries
}

fn save_settings_to_file(is_dark bool, width int, height int) {
	settings := Settings{
		is_dark_mode: is_dark
		win_width: width
		win_height: height
	}
	data := json.encode(settings)
	os.write_file('settings.json', data) or {}
}

fn read_settings_from_file() (bool, int, int) {
	if !os.exists('settings.json') {
		return true, 800, 600 // Default to dark mode, 800x600
	}
	content := os.read_file('settings.json') or { return true, 800, 600 }
	if content.trim_space() == '' {
		return true, 800, 600
	}
	settings := json.decode(Settings, content) or { return true, 800, 600 }
	width := if settings.win_width > 0 { settings.win_width } else { 800 }
	height := if settings.win_height > 0 { settings.win_height } else { 600 }
	return settings.is_dark_mode, width, height
}

fn start_create(mut app App) {
	app.mode = .create
	app.title_input.text = ''
	app.title_input.cursor_pos = 0
	app.content_input.text = ''
	app.content_input.cursor_pos = 0
	app.tags_input.text = ''
	app.tags_input.cursor_pos = 0
	app.mood_input.text = 'Happy'
	app.title_input.is_focused = true
	app.content_input.is_focused = false
	app.tags_input.is_focused = false
	app.search_input.is_focused = false
	app.date_from_input.is_focused = false
	app.date_to_input.is_focused = false
}

fn start_edit(mut app App) {
	if app.selected_index == -1 { return }
	
	// Find correct entry in filtered list
	filtered_entries := app.get_filtered_entries()
	if app.selected_index >= filtered_entries.len { return }
	entry := filtered_entries[app.selected_index]
	
	app.mode = .edit
	app.title_input.text = entry.title
	app.title_input.cursor_pos = entry.title.runes().len
	app.content_input.text = entry.content
	app.content_input.cursor_pos = entry.content.runes().len
	app.tags_input.text = entry.tags.join(', ')
	app.tags_input.cursor_pos = app.tags_input.text.runes().len
	app.mood_input.text = entry.mood
	app.title_input.is_focused = true
	app.content_input.is_focused = false
	app.tags_input.is_focused = false
	app.search_input.is_focused = false
	app.date_from_input.is_focused = false
	app.date_to_input.is_focused = false
}

fn (app &App) get_filtered_entries() []Entry {
	mut filtered := []Entry{}
	for entry in app.entries {
		if entry.matches_search(app.search_input.text) {
			if app.filter_mood == 'All' || entry.mood == app.filter_mood {
				if entry.matches_date_filter(app.filter_date, app.date_from_input.text, app.date_to_input.text) {
					filtered << entry
				}
			}
		}
	}
	return filtered
}

fn delete_entry(mut app App) {
	if app.selected_index == -1 { return }
	filtered_entries := app.get_filtered_entries()
	if app.selected_index >= filtered_entries.len { return }
	target_entry := filtered_entries[app.selected_index]

	// Remove from main list
	mut target_index := -1
	for idx, entry in app.entries {
		if entry.id == target_entry.id {
			target_index = idx
			break
		}
	}
	if target_index != -1 {
		app.entries.delete(target_index)
	}
	
	filtered := app.get_filtered_entries()
	app.selected_index = if filtered.len > 0 { 0 } else { -1 }
	write_entries_to_file(app.entries)
	app.mode = .view
}

fn save_entry(mut app App) {
	title := app.title_input.text.trim_space()
	if title == '' {
		return
	}
	content := app.content_input.text
	tags_str := app.tags_input.text
	tags := tags_str.split(',').map(it.trim_space()).filter(it.len > 0)
	mood := app.mood_input.text
	date := time.now().custom_format('YYYY-MM-DD')

	if app.mode == .edit {
		filtered := app.get_filtered_entries()
		if app.selected_index >= 0 && app.selected_index < filtered.len {
			target_id := filtered[app.selected_index].id
			for mut entry in app.entries {
				if entry.id == target_id {
					entry.title = title
					entry.content = content
					entry.mood = mood
					entry.tags = tags
					break
				}
			}
		}
	} else {
		new_entry := Entry{
			id: '${time.now().unix()}'
			title: title
			content: content
			date: date
			mood: mood
			tags: tags
		}
		app.entries.insert(0, new_entry)
		app.selected_index = 0
	}
	write_entries_to_file(app.entries)
	app.mode = .view
}

fn find_line_starts(text string, lines []string) []int {
	runes := text.runes()
	mut starts := []int{len: lines.len, init: 0}
	mut current_pos := 0
	for idx, line in lines {
		line_runes := line.runes()
		mut found := false
		for i := current_pos; i <= runes.len - line_runes.len; i++ {
			mut is_match := true
			for j := 0; j < line_runes.len; j++ {
				if runes[i + j] != line_runes[j] {
					is_match = false
					break
				}
			}
			if is_match {
				starts[idx] = i
				current_pos = i + line_runes.len
				found = true
				break
			}
		}
		if !found {
			starts[idx] = current_pos
		}
	}
	return starts
}

fn position_cursor_singleline(mx int, x int, w int, size int, mut input TextInput, ctx &gg.Context) {
	ctx.set_text_cfg(size: size)
	runes := input.text.runes()
	mut min_dist := 999999
	mut best_col := 0
	for col in 0 .. runes.len + 1 {
		sub_text := runes[0..col].string()
		mut sub_w, _ := ctx.text_size(sub_text)
		if sub_w == 0 {
			sub_w = (col * size * 11) / 20
		}
		dist := x + 10 + sub_w - mx
		mut abs_dist := dist
		if abs_dist < 0 {
			abs_dist = -abs_dist
		}
		if abs_dist < min_dist {
			min_dist = abs_dist
			best_col = col
		}
	}
	input.cursor_pos = best_col
}

fn position_cursor_multiline(mx int, my int, x int, y int, w int, h int, size int, mut input TextInput, ctx &gg.Context) {
	ctx.set_text_cfg(size: size)
	lines := wrap_text(input.text, w - 20, size, ctx)
	starts := find_line_starts(input.text, lines)
	
	line_height := 20
	mut clicked_line_idx := (my - (y + 8)) / line_height
	if clicked_line_idx < 0 {
		clicked_line_idx = 0
	}
	if clicked_line_idx >= lines.len {
		clicked_line_idx = lines.len - 1
	}
	
	if lines.len == 0 {
		input.cursor_pos = 0
		return
	}
	
	line_text := lines[clicked_line_idx]
	line_runes := line_text.runes()
	
	mut min_dist := 999999
	mut best_col := 0
	for col in 0 .. line_runes.len + 1 {
		sub_text := line_runes[0..col].string()
		mut sub_w, _ := ctx.text_size(sub_text)
		if sub_w == 0 {
			sub_w = (col * size * 11) / 20
		}
		dist := x + 10 + sub_w - mx
		mut abs_dist := dist
		if abs_dist < 0 {
			abs_dist = -abs_dist
		}
		if abs_dist < min_dist {
			min_dist = abs_dist
			best_col = col
		}
	}
	
	input.cursor_pos = starts[clicked_line_idx] + best_col
	runes := input.text.runes()
	if input.cursor_pos > runes.len {
		input.cursor_pos = runes.len
	}
}

fn insert_char(mut input TextInput, ch string) {
	mut runes := input.text.runes()
	if input.cursor_pos < 0 {
		input.cursor_pos = 0
	}
	if input.cursor_pos > runes.len {
		input.cursor_pos = runes.len
	}
	ch_runes := ch.runes()
	for idx, r in ch_runes {
		runes.insert(input.cursor_pos + idx, r)
	}
	input.text = runes.string()
	input.cursor_pos += ch_runes.len
}

fn delete_char(mut input TextInput) {
	mut runes := input.text.runes()
	if runes.len == 0 || input.cursor_pos <= 0 {
		return
	}
	if input.cursor_pos > runes.len {
		input.cursor_pos = runes.len
	}
	runes.delete(input.cursor_pos - 1)
	input.text = runes.string()
	input.cursor_pos--
}

fn delete_forward_char(mut input TextInput) {
	mut runes := input.text.runes()
	if runes.len == 0 || input.cursor_pos >= runes.len {
		return
	}
	runes.delete(input.cursor_pos)
	input.text = runes.string()
}

fn move_cursor_left(mut input TextInput) {
	if input.cursor_pos > 0 {
		input.cursor_pos--
	}
}

fn move_cursor_right(mut input TextInput) {
	runes := input.text.runes()
	if input.cursor_pos < runes.len {
		input.cursor_pos++
	}
}

fn move_cursor_up(mut input TextInput, w int, ctx &gg.Context) {
	lines := wrap_text(input.text, w - 20, 14, ctx)
	starts := find_line_starts(input.text, lines)
	
	mut cursor_line_idx := -1
	for idx, start_idx in starts {
		line_runes := lines[idx].runes()
		if input.cursor_pos >= start_idx && input.cursor_pos <= start_idx + line_runes.len {
			cursor_line_idx = idx
		}
	}
	
	if cursor_line_idx > 0 {
		start_idx := starts[cursor_line_idx]
		offset := input.cursor_pos - start_idx
		
		prev_line_start := starts[cursor_line_idx - 1]
		prev_line_runes := lines[cursor_line_idx - 1].runes()
		
		mut new_offset := offset
		if new_offset > prev_line_runes.len {
			new_offset = prev_line_runes.len
		}
		input.cursor_pos = prev_line_start + new_offset
	} else if cursor_line_idx == 0 {
		input.cursor_pos = 0
	}
}

fn move_cursor_down(mut input TextInput, w int, ctx &gg.Context) {
	lines := wrap_text(input.text, w - 20, 14, ctx)
	starts := find_line_starts(input.text, lines)
	
	mut cursor_line_idx := -1
	for idx, start_idx in starts {
		line_runes := lines[idx].runes()
		if input.cursor_pos >= start_idx && input.cursor_pos <= start_idx + line_runes.len {
			cursor_line_idx = idx
		}
	}
	
	if cursor_line_idx != -1 && cursor_line_idx < lines.len - 1 {
		start_idx := starts[cursor_line_idx]
		offset := input.cursor_pos - start_idx
		
		next_line_start := starts[cursor_line_idx + 1]
		next_line_runes := lines[cursor_line_idx + 1].runes()
		
		mut new_offset := offset
		if new_offset > next_line_runes.len {
			new_offset = next_line_runes.len
		}
		input.cursor_pos = next_line_start + new_offset
	} else if cursor_line_idx == lines.len - 1 {
		runes := input.text.runes()
		input.cursor_pos = runes.len
	}
}

fn wrap_text(text string, max_width int, size int, ctx &gg.Context) []string {
	ctx.set_text_cfg(size: size)
	words := text.split(' ')
	mut lines := []string{}
	mut current_line := ''
	for word in words {
		if word.contains('\n') {
			parts := word.split('\n')
			for i, part in parts {
				test_line := if current_line == '' { part } else { current_line + ' ' + part }
				mut w, _ := ctx.text_size(test_line)
				if w == 0 {
					w = (test_line.len * size * 11) / 20
				}
				if w > max_width {
					lines << current_line
					current_line = part
				} else {
					current_line = test_line
				}
				if i < parts.len - 1 {
					lines << current_line
					current_line = ''
				}
			}
			continue
		}
		test_line := if current_line == '' { word } else { current_line + ' ' + word }
		mut w, _ := ctx.text_size(test_line)
		if w == 0 {
			w = (test_line.len * size * 11) / 20
		}
		if w > max_width {
			lines << current_line
			current_line = word
		} else {
			current_line = test_line
		}
	}
	if current_line != '' {
		lines << current_line
	}
	return lines
}

fn draw_text_field(x int, y int, w int, h int, input TextInput, ctx &gg.Context, cursor_ticks int, placeholder string, t Theme) {
	if input.is_focused {
		ctx.draw_rect_filled(x, y, w, h, t.input_bg)
		ctx.draw_rect_empty(x, y, w, h, t.accent)
	} else {
		ctx.draw_rect_filled(x, y, w, h, t.input_bg)
		ctx.draw_rect_empty(x, y, w, h, t.border)
	}

	mut text_to_draw := input.text
	mut color := t.text_primary
	if text_to_draw == '' && !input.is_focused {
		text_to_draw = placeholder
		color = t.text_sec
		ctx.draw_text(x + 10, y + 8, text_to_draw, size: 14, color: color)
	} else {
		runes := text_to_draw.runes()
		mut cursor_x := x + 10
		if input.is_focused {
			sub_w := if input.cursor_pos > 0 { 
				mut sw, _ := ctx.text_size(runes[0..input.cursor_pos].string())
				if sw == 0 { sw = (input.cursor_pos * 14 * 11) / 20 }
				sw
			} else { 0 }
			cursor_x += sub_w
		}
		
		ctx.draw_text(x + 10, y + 8, text_to_draw, size: 14, color: color)
		
		if input.is_focused && (cursor_ticks % 60 < 30) {
			ctx.draw_line(cursor_x, y + 8, cursor_x, y + 26, t.accent)
		}
	}
}

fn draw_text_field_multiline(x int, y int, w int, h int, input TextInput, ctx &gg.Context, cursor_ticks int, t Theme) {
	if input.is_focused {
		ctx.draw_rect_filled(x, y, w, h, t.input_bg)
		ctx.draw_rect_empty(x, y, w, h, t.accent)
	} else {
		ctx.draw_rect_filled(x, y, w, h, t.input_bg)
		ctx.draw_rect_empty(x, y, w, h, t.border)
	}

	lines := wrap_text(input.text, w - 20, 14, ctx)
	starts := find_line_starts(input.text, lines)

	for idx, line in lines {
		if 8 + idx * 20 + 20 > h {
			break
		}
		ctx.draw_text(x + 10, y + 8 + idx * 20, line, size: 14, color: t.text_primary)
	}

	if input.is_focused && (cursor_ticks % 60 < 30) {
		mut cursor_line_idx := -1
		for idx, start_idx in starts {
			line_runes := lines[idx].runes()
			if input.cursor_pos >= start_idx && input.cursor_pos <= start_idx + line_runes.len {
				cursor_line_idx = idx
			}
		}
		
		if cursor_line_idx != -1 {
			start_idx := starts[cursor_line_idx]
			offset := input.cursor_pos - start_idx
			line_text := lines[cursor_line_idx]
			line_runes := line_text.runes()
			
			safe_offset := if offset < 0 { 0 } else if offset > line_runes.len { line_runes.len } else { offset }
			
			sub_text := line_runes[0..safe_offset].string()
			mut sub_w, _ := ctx.text_size(sub_text)
			if sub_w == 0 {
				sub_w = (safe_offset * 14 * 11) / 20
			}
			
			cx := x + 10 + sub_w
			cy := y + 8 + cursor_line_idx * 20
			if cy + 18 <= y + h {
				ctx.draw_line(cx, cy, cx, cy + 16, t.accent)
			}
		}
	}
}

fn draw_view_mode(app &App, t Theme) {
	filtered := app.get_filtered_entries()
	if app.selected_index == -1 || filtered.len == 0 || app.selected_index >= filtered.len {
		app.ctx.draw_text(380, 260, 'Welcome to MindSpace', size: 24, color: t.accent, bold: true)
		app.ctx.draw_text(350, 300, 'Select an entry from the sidebar or write a new one.', size: 14, color: t.text_sec)
		return
	}

	entry := filtered[app.selected_index]
	
	app.ctx.draw_text(280, 40, entry.title, size: 26, color: t.text_primary, bold: true)
	app.ctx.draw_text(280, 85, 'Date: ${entry.date}    Mood: ${entry.mood}', size: 14, color: gg.rgb(16, 185, 129))

	if entry.tags.len > 0 {
		mut tx := 280
		for tag in entry.tags {
			tag_str := '#${tag}'
			tw, _ := app.ctx.text_size(tag_str)
			app.ctx.draw_rect_filled(tx, 115, tw + 10, 22, t.input_bg)
			app.ctx.draw_text(tx + 5, 118, tag_str, size: 12, color: gg.rgb(6, 182, 212))
			tx += tw + 18
		}
	}

	lines := wrap_text(entry.content, app.win_width - 310, 15, app.ctx)
	for idx, line in lines {
		y_pos := 160 + idx * 22 - app.content_scroll_y
		if y_pos >= 150 && y_pos < app.win_height - 80 {
			app.ctx.draw_text(280, y_pos, line, size: 15, color: t.text_primary)
		}
	}

	edit_btn_color := if app.hover_edit { t.card_sel } else { t.input_bg }
	app.ctx.draw_rect_filled(280, app.win_height - 60, 100, 45, edit_btn_color)
	app.ctx.draw_rect_empty(280, app.win_height - 60, 100, 45, t.border)
	app.ctx.draw_text(315, app.win_height - 48, 'Edit', size: 14, color: t.text_primary, bold: true)

	delete_btn_color := if app.hover_delete { gg.rgb(220, 38, 38) } else { gg.rgb(185, 28, 28) }
	app.ctx.draw_rect_filled(400, app.win_height - 60, 100, 45, delete_btn_color)
	app.ctx.draw_text(428, app.win_height - 48, 'Delete', size: 14, color: gg.white, bold: true)
}

fn draw_form_mode(app &App, t Theme) {
	title_label := if app.mode == .edit { 'Edit Journal Entry' } else { 'Create Journal Entry' }
	app.ctx.draw_text(280, 30, title_label, size: 22, color: t.accent, bold: true)

	input_w := app.win_width - 310

	app.ctx.draw_text(280, 65, 'Title', size: 12, color: t.text_sec)
	draw_text_field(280, 80, input_w, 35, app.title_input, app.ctx, app.cursor_ticks, 'Title of your entry', t)

	app.ctx.draw_text(280, 130, 'Date', size: 12, color: t.text_sec)
	date_str := if app.mode == .edit { 
		filtered := app.get_filtered_entries()
		if app.selected_index >= 0 && app.selected_index < filtered.len { filtered[app.selected_index].date } else { '' }
	} else { time.now().custom_format('YYYY-MM-DD') }
	app.ctx.draw_rect_filled(280, 145, 120, 35, t.input_bg)
	app.ctx.draw_rect_empty(280, 145, 120, 35, t.border)
	app.ctx.draw_text(290, 154, date_str, size: 14, color: t.text_sec)

	app.ctx.draw_text(420, 130, 'Mood', size: 12, color: t.text_sec)
	moods := ['Happy', 'Excited', 'Peaceful', 'Neutral', 'Sad', 'Angry', 'Tired']
	for i, mood in moods {
		col := i % 4
		row := i / 4
		bx := 420 + col * 80
		by := 145 + row * 28
		if app.mood_input.text == mood {
			app.ctx.draw_rect_filled(bx, by, 75, 25, t.accent)
			app.ctx.draw_text(bx + 8, by + 5, mood, size: 12, color: gg.white)
		} else if app.hover_moods.len > i && app.hover_moods[i] {
			app.ctx.draw_rect_filled(bx, by, 75, 25, t.card_sel)
			app.ctx.draw_text(bx + 8, by + 5, mood, size: 12, color: t.text_primary)
		} else {
			app.ctx.draw_rect_filled(bx, by, 75, 25, t.input_bg)
			app.ctx.draw_rect_empty(bx, by, 75, 25, t.border)
			app.ctx.draw_text(bx + 8, by + 5, mood, size: 12, color: t.text_sec)
		}
	}

	app.ctx.draw_text(280, 215, 'Tags (separated by commas)', size: 12, color: t.text_sec)
	draw_text_field(280, 230, input_w, 35, app.tags_input, app.ctx, app.cursor_ticks, 'e.g. reflection, ideas', t)

	app.ctx.draw_text(280, 280, 'Content', size: 12, color: t.text_sec)
	content_h := app.win_height - 375
	draw_text_field_multiline(280, 295, input_w, content_h, app.content_input, app.ctx, app.cursor_ticks, t)

	cancel_btn_color := if app.hover_cancel { t.card_sel } else { t.input_bg }
	app.ctx.draw_rect_filled(app.win_width - 250, app.win_height - 60, 100, 40, cancel_btn_color)
	app.ctx.draw_rect_empty(app.win_width - 250, app.win_height - 60, 100, 40, t.border)
	app.ctx.draw_text(app.win_width - 225, app.win_height - 49, 'Cancel', size: 14, color: t.text_primary, bold: true)

	save_btn_color := if app.hover_save { gg.rgb(167, 139, 250) } else { t.accent }
	app.ctx.draw_rect_filled(app.win_width - 130, app.win_height - 60, 100, 40, save_btn_color)
	app.ctx.draw_text(app.win_width - 98, app.win_height - 49, 'Save', size: 14, color: gg.white, bold: true)
}

fn handle_click(mx int, my int, mut app App) {
	os.write_file('click.log', 'click: mx=${mx}, my=${my}, scale=${app.ctx.scale}, win=${app.win_width}x${app.win_height}\n') or {}
	if mx >= 20 && mx <= 230 && my >= app.win_height - 40 && my <= app.win_height - 10 {
		app.ctx.quit()
		return
	}

	if mx >= 180 && mx <= 240 && my >= 20 && my <= 45 {
		app.is_dark_mode = !app.is_dark_mode
		save_settings_to_file(app.is_dark_mode, app.win_width, app.win_height)
		return
	}

	if mx >= 20 && mx <= 230 && my >= 60 && my <= 95 {
		start_create(mut app)
		return
	}

	if mx >= 20 && mx <= 230 && my >= 110 && my <= 140 {
		app.search_input.is_focused = true
		app.title_input.is_focused = false
		app.content_input.is_focused = false
		app.tags_input.is_focused = false
		app.date_from_input.is_focused = false
		app.date_to_input.is_focused = false
		position_cursor_singleline(mx, 20, 210, 14, mut app.search_input, app.ctx)
		return
	} else {
		app.search_input.is_focused = false
	}

	// Sidebar "Mood Filter" button: x: 20, y: 150, w: 210, h: 30
	if mx >= 20 && mx <= 230 && my >= 150 && my <= 180 {
		moods := ['All', 'Happy', 'Excited', 'Peaceful', 'Neutral', 'Sad', 'Angry', 'Tired']
		mut next_idx := 0
		for idx, mood in moods {
			if mood == app.filter_mood {
				next_idx = (idx + 1) % moods.len
				break
			}
		}
		app.filter_mood = moods[next_idx]
		filtered := app.get_filtered_entries()
		app.selected_index = if filtered.len > 0 { 0 } else { -1 }
		app.list_scroll_y = 0
		app.date_from_input.is_focused = false
		app.date_to_input.is_focused = false
		return
	}

	// Sidebar "Date Filter" button: x: 20, y: 190, w: 210, h: 30
	if mx >= 20 && mx <= 230 && my >= 190 && my <= 220 {
		dates := ['All Time', 'Today', 'This Week', 'This Month', 'This Year', 'Custom Range']
		mut next_idx := 0
		for idx, d in dates {
			if d == app.filter_date {
				next_idx = (idx + 1) % dates.len
				break
			}
		}
		app.filter_date = dates[next_idx]
		filtered := app.get_filtered_entries()
		app.selected_index = if filtered.len > 0 { 0 } else { -1 }
		app.list_scroll_y = 0
		app.date_from_input.is_focused = false
		app.date_to_input.is_focused = false
		return
	}

	if app.filter_date == 'Custom Range' {
		if mx >= 20 && mx <= 120 && my >= 240 && my <= 270 {
			app.date_from_input.is_focused = true
			app.date_to_input.is_focused = false
			app.title_input.is_focused = false
			app.content_input.is_focused = false
			app.tags_input.is_focused = false
			app.search_input.is_focused = false
			position_cursor_singleline(mx, 20, 100, 14, mut app.date_from_input, app.ctx)
			return
		}
		if mx >= 130 && mx <= 230 && my >= 240 && my <= 270 {
			app.date_from_input.is_focused = false
			app.date_to_input.is_focused = true
			app.title_input.is_focused = false
			app.content_input.is_focused = false
			app.tags_input.is_focused = false
			app.search_input.is_focused = false
			position_cursor_singleline(mx, 130, 100, 14, mut app.date_to_input, app.ctx)
			return
		}
	}

	list_y_start := if app.filter_date == 'Custom Range' { 280 } else { 230 }

	// Sidebar list starts at y: list_y_start.
	filtered_entries := app.get_filtered_entries()
	if mx >= 10 && mx <= 240 && my >= list_y_start && my < app.win_height - 50 {
		y_offset := my - list_y_start + app.list_scroll_y
		item_index := y_offset / 70
		if y_offset % 70 <= 60 && item_index >= 0 && item_index < filtered_entries.len {
			app.selected_index = item_index
			app.mode = .view
			app.content_scroll_y = 0
			app.title_input.is_focused = false
			app.content_input.is_focused = false
			app.tags_input.is_focused = false
			app.date_from_input.is_focused = false
			app.date_to_input.is_focused = false
			return
		}
	}

	if app.mode == .view {
		if app.selected_index != -1 {
			if mx >= 280 && mx <= 380 && my >= app.win_height - 60 && my <= app.win_height - 15 {
				start_edit(mut app)
				return
			}
			if mx >= 400 && mx <= 500 && my >= app.win_height - 60 && my <= app.win_height - 15 {
				delete_entry(mut app)
				return
			}
		}
	} else {
		input_w := app.win_width - 310
		if mx >= 280 && mx <= 280 + input_w && my >= 80 && my <= 115 {
			app.title_input.is_focused = true
			app.content_input.is_focused = false
			app.tags_input.is_focused = false
			app.date_from_input.is_focused = false
			app.date_to_input.is_focused = false
			position_cursor_singleline(mx, 280, input_w, 14, mut app.title_input, app.ctx)
			return
		}
		if mx >= 280 && mx <= 280 + input_w && my >= 230 && my <= 265 {
			app.title_input.is_focused = false
			app.content_input.is_focused = false
			app.tags_input.is_focused = true
			app.date_from_input.is_focused = false
			app.date_to_input.is_focused = false
			position_cursor_singleline(mx, 280, input_w, 14, mut app.tags_input, app.ctx)
			return
		}
		content_h := app.win_height - 375
		if mx >= 280 && mx <= 280 + input_w && my >= 295 && my <= 295 + content_h {
			app.title_input.is_focused = false
			app.content_input.is_focused = true
			app.tags_input.is_focused = false
			app.date_from_input.is_focused = false
			app.date_to_input.is_focused = false
			position_cursor_multiline(mx, my, 280, 295, input_w, content_h, 15, mut app.content_input, app.ctx)
			return
		}

		moods := ['Happy', 'Excited', 'Peaceful', 'Neutral', 'Sad', 'Angry', 'Tired']
		for i, mood in moods {
			col := i % 4
			row := i / 4
			bx := 420 + col * 80
			by := 145 + row * 28
			if mx >= bx && mx <= bx + 75 && my >= by && my <= by + 25 {
				app.mood_input.text = mood
				app.title_input.is_focused = false
				app.content_input.is_focused = false
				app.tags_input.is_focused = false
				app.date_from_input.is_focused = false
				app.date_to_input.is_focused = false
				return
			}
		}

		if mx >= app.win_width - 130 && mx <= app.win_width - 30 && my >= app.win_height - 60 && my <= app.win_height - 20 {
			save_entry(mut app)
			return
		}
		if mx >= app.win_width - 250 && mx <= app.win_width - 150 && my >= app.win_height - 60 && my <= app.win_height - 20 {
			app.mode = .view
			return
		}
	}

	app.title_input.is_focused = false
	app.content_input.is_focused = false
	app.tags_input.is_focused = false
	app.search_input.is_focused = false
	app.date_from_input.is_focused = false
	app.date_to_input.is_focused = false
}

fn handle_move(mx int, my int, mut app App) {
	app.hover_theme = mx >= 180 && mx <= 240 && my >= 20 && my <= 45
	app.hover_new = mx >= 20 && mx <= 230 && my >= 60 && my <= 95
	app.hover_filter_mood = mx >= 20 && mx <= 230 && my >= 150 && my <= 180
	app.hover_filter_date = mx >= 20 && mx <= 230 && my >= 190 && my <= 220
	app.hover_exit = mx >= 20 && mx <= 230 && my >= app.win_height - 40 && my <= app.win_height - 10

	if app.mode == .view {
		app.hover_edit = mx >= 280 && mx <= 380 && my >= app.win_height - 60 && my <= app.win_height - 15
		app.hover_delete = mx >= 400 && mx <= 500 && my >= app.win_height - 60 && my <= app.win_height - 15
	} else {
		app.hover_save = mx >= app.win_width - 130 && mx <= app.win_width - 30 && my >= app.win_height - 60 && my <= app.win_height - 20
		app.hover_cancel = mx >= app.win_width - 250 && mx <= app.win_width - 150 && my >= app.win_height - 60 && my <= app.win_height - 20
		
		app.hover_moods = []bool{len: 7, init: false}
		for i in 0 .. 7 {
			col := i % 4
			row := i / 4
			bx := 420 + col * 80
			by := 145 + row * 28
			if mx >= bx && mx <= bx + 75 && my >= by && my <= by + 25 {
				app.hover_moods[i] = true
			}
		}
	}
}

fn handle_char(char_code u32, mut app App) {
	if char_code < 32 || char_code == 127 {
		return
	}
	ch_str := rune(char_code).str()
	if app.title_input.is_focused {
		insert_char(mut app.title_input, ch_str)
	} else if app.content_input.is_focused {
		insert_char(mut app.content_input, ch_str)
	} else if app.tags_input.is_focused {
		insert_char(mut app.tags_input, ch_str)
	} else if app.search_input.is_focused {
		insert_char(mut app.search_input, ch_str)
		filtered := app.get_filtered_entries()
		if filtered.len > 0 {
			app.selected_index = 0
		} else {
			app.selected_index = -1
		}
	} else if app.date_from_input.is_focused {
		insert_char(mut app.date_from_input, ch_str)
		filtered := app.get_filtered_entries()
		app.selected_index = if filtered.len > 0 { 0 } else { -1 }
		app.list_scroll_y = 0
	} else if app.date_to_input.is_focused {
		insert_char(mut app.date_to_input, ch_str)
		filtered := app.get_filtered_entries()
		app.selected_index = if filtered.len > 0 { 0 } else { -1 }
		app.list_scroll_y = 0
	}
}

fn handle_key(key_code gg.KeyCode, mut app App) {
	if key_code == .backspace {
		if app.title_input.is_focused {
			delete_char(mut app.title_input)
		} else if app.content_input.is_focused {
			delete_char(mut app.content_input)
		} else if app.tags_input.is_focused {
			delete_char(mut app.tags_input)
		} else if app.search_input.is_focused {
			delete_char(mut app.search_input)
			filtered := app.get_filtered_entries()
			if filtered.len > 0 {
				app.selected_index = 0
			} else {
				app.selected_index = -1
			}
		} else if app.date_from_input.is_focused {
			delete_char(mut app.date_from_input)
			filtered := app.get_filtered_entries()
			app.selected_index = if filtered.len > 0 { 0 } else { -1 }
			app.list_scroll_y = 0
		} else if app.date_to_input.is_focused {
			delete_char(mut app.date_to_input)
			filtered := app.get_filtered_entries()
			app.selected_index = if filtered.len > 0 { 0 } else { -1 }
			app.list_scroll_y = 0
		}
	} else if key_code == .delete {
		if app.title_input.is_focused {
			delete_forward_char(mut app.title_input)
		} else if app.content_input.is_focused {
			delete_forward_char(mut app.content_input)
		} else if app.tags_input.is_focused {
			delete_forward_char(mut app.tags_input)
		} else if app.search_input.is_focused {
			delete_forward_char(mut app.search_input)
			filtered := app.get_filtered_entries()
			if filtered.len > 0 {
				app.selected_index = 0
			} else {
				app.selected_index = -1
			}
		} else if app.date_from_input.is_focused {
			delete_forward_char(mut app.date_from_input)
			filtered := app.get_filtered_entries()
			app.selected_index = if filtered.len > 0 { 0 } else { -1 }
			app.list_scroll_y = 0
		} else if app.date_to_input.is_focused {
			delete_forward_char(mut app.date_to_input)
			filtered := app.get_filtered_entries()
			app.selected_index = if filtered.len > 0 { 0 } else { -1 }
			app.list_scroll_y = 0
		}
	} else if key_code == .enter {
		if app.content_input.is_focused {
			insert_char(mut app.content_input, '\n')
		}
	} else if key_code == .tab {
		if app.title_input.is_focused {
			app.title_input.is_focused = false
			app.tags_input.is_focused = true
		} else if app.tags_input.is_focused {
			app.tags_input.is_focused = false
			app.content_input.is_focused = true
		} else if app.content_input.is_focused {
			insert_char(mut app.content_input, '    ')
		} else if app.date_from_input.is_focused {
			app.date_from_input.is_focused = false
			app.date_to_input.is_focused = true
		} else if app.date_to_input.is_focused {
			app.date_to_input.is_focused = false
			app.date_from_input.is_focused = true
		}
	} else if key_code == .left {
		if app.title_input.is_focused {
			move_cursor_left(mut app.title_input)
		} else if app.content_input.is_focused {
			move_cursor_left(mut app.content_input)
		} else if app.tags_input.is_focused {
			move_cursor_left(mut app.tags_input)
		} else if app.search_input.is_focused {
			move_cursor_left(mut app.search_input)
		} else if app.date_from_input.is_focused {
			move_cursor_left(mut app.date_from_input)
		} else if app.date_to_input.is_focused {
			move_cursor_left(mut app.date_to_input)
		}
	} else if key_code == .right {
		if app.title_input.is_focused {
			move_cursor_right(mut app.title_input)
		} else if app.content_input.is_focused {
			move_cursor_right(mut app.content_input)
		} else if app.tags_input.is_focused {
			move_cursor_right(mut app.tags_input)
		} else if app.search_input.is_focused {
			move_cursor_right(mut app.search_input)
		} else if app.date_from_input.is_focused {
			move_cursor_right(mut app.date_from_input)
		} else if app.date_to_input.is_focused {
			move_cursor_right(mut app.date_to_input)
		}
	} else if key_code == .up {
		if app.content_input.is_focused {
			move_cursor_up(mut app.content_input, app.win_width - 310, app.ctx)
		}
	} else if key_code == .down {
		if app.content_input.is_focused {
			move_cursor_down(mut app.content_input, app.win_width - 310, app.ctx)
		}
	}
}

fn delete_last_char(s string) string {
	if s.len == 0 {
		return ''
	}
	runes := s.runes()
	if runes.len == 0 {
		return ''
	}
	return runes[0 .. runes.len - 1].string()
}

fn handle_scroll(e &gg.Event, mut app App) {
	scroll_speed := 15
	if e.mouse_x < app.sidebar_width {
		app.list_scroll_y -= int(e.scroll_y * scroll_speed)
		if app.list_scroll_y < 0 {
			app.list_scroll_y = 0
		}
		filtered := app.get_filtered_entries()
		list_y_start := if app.filter_date == 'Custom Range' { 280 } else { 230 }
		max_scroll := filtered.len * 70 - (app.win_height - 50 - list_y_start)
		if max_scroll < 0 {
			app.list_scroll_y = 0
		} else if app.list_scroll_y > max_scroll {
			app.list_scroll_y = max_scroll
		}
	} else {
		app.content_scroll_y -= int(e.scroll_y * scroll_speed)
		if app.content_scroll_y < 0 {
			app.content_scroll_y = 0
		}
		if app.selected_index >= 0 && app.mode == .view {
			filtered := app.get_filtered_entries()
			if app.selected_index < filtered.len {
				entry := filtered[app.selected_index]
				lines := wrap_text(entry.content, app.win_width - 310, 15, app.ctx)
				max_scroll := lines.len * 22 - (app.win_height - 240)
				if max_scroll < 0 {
					app.content_scroll_y = 0
				} else if app.content_scroll_y > max_scroll {
					app.content_scroll_y = max_scroll
				}
			}
		}
	}
}

fn on_frame(mut app App) {
	ws := gg.window_size()
	mut size_changed := false
	if ws.width > 0 && ws.width != app.win_width {
		app.win_width = ws.width
		size_changed = true
	}
	if ws.height > 0 && ws.height != app.win_height {
		app.win_height = ws.height
		size_changed = true
	}
	if size_changed {
		save_settings_to_file(app.is_dark_mode, app.win_width, app.win_height)
	}

	t := get_theme(app.is_dark_mode)
	app.ctx.begin()
	
	app.cursor_ticks++

	// 1. Draw Sidebar
	app.ctx.draw_rect_filled(0, 0, app.sidebar_width, app.win_height, t.bg_sidebar)
	app.ctx.draw_line(app.sidebar_width, 0, app.sidebar_width, app.win_height, t.border)

	// Sidebar Title
	app.ctx.draw_text(20, 20, 'MindSpace', size: 22, color: t.accent, bold: true)

	// Theme Toggle Button
	theme_btn_color := if app.hover_theme { t.card_sel } else { t.input_bg }
	theme_btn_label := if app.is_dark_mode { 'Light' } else { 'Dark' }
	app.ctx.draw_rect_filled(170, 20, 65, 25, theme_btn_color)
	app.ctx.draw_rect_empty(170, 20, 65, 25, t.border)
	app.ctx.draw_text(182, 25, theme_btn_label, size: 12, color: t.text_primary)

	// Sidebar "+ New Entry" Button
	new_btn_color := if app.hover_new { gg.rgb(167, 139, 250) } else { t.accent }
	app.ctx.draw_rect_filled(20, 60, 210, 35, new_btn_color)
	app.ctx.draw_text(80, 68, '+ New Entry', size: 14, color: gg.white, bold: true)

	// Sidebar "Search" Input Field
	draw_text_field(20, 110, 210, 32, app.search_input, app.ctx, app.cursor_ticks, 'Search notes...', t)

	// Sidebar "Mood Filter" Cycling Button
	filter_btn_color := if app.hover_filter_mood { t.card_sel } else { t.input_bg }
	app.ctx.draw_rect_filled(20, 150, 210, 30, filter_btn_color)
	app.ctx.draw_rect_empty(20, 150, 210, 30, t.border)
	app.ctx.draw_text(30, 158, 'Mood: ${app.filter_mood}', size: 13, color: t.text_primary)

	// Sidebar "Date Filter" Cycling Button
	filter_date_btn_color := if app.hover_filter_date { t.card_sel } else { t.input_bg }
	app.ctx.draw_rect_filled(20, 190, 210, 30, filter_date_btn_color)
	app.ctx.draw_rect_empty(20, 190, 210, 30, t.border)
	app.ctx.draw_text(30, 198, 'Time: ${app.filter_date}', size: 13, color: t.text_primary)

	if app.filter_date == 'Custom Range' {
		// Draw format helper text
		app.ctx.draw_text(20, 226, 'Range (YYYY-MM-DD):', size: 11, color: t.text_sec)
		// Draw "From" input
		draw_text_field(20, 240, 100, 30, app.date_from_input, app.ctx, app.cursor_ticks, 'From', t)
		// Draw "To" input
		draw_text_field(130, 240, 100, 30, app.date_to_input, app.ctx, app.cursor_ticks, 'To', t)
	}

	// Sidebar list starts at y: list_y_start
	list_y_start := if app.filter_date == 'Custom Range' { 280 } else { 230 }
	filtered := app.get_filtered_entries()
	for i, entry in filtered {
		by := list_y_start + i * 70 - app.list_scroll_y
		if by < list_y_start - 10 || by > app.win_height - 110 {
			continue
		}
		
		if i == app.selected_index {
			app.ctx.draw_rect_filled(10, by, 230, 60, t.card_sel)
			app.ctx.draw_rect_empty(10, by, 230, 60, t.accent)
		} else {
			app.ctx.draw_rect_filled(10, by, 230, 60, t.input_bg)
			app.ctx.draw_rect_empty(10, by, 230, 60, t.border)
		}
		title_trunc := if entry.title.len > 18 { entry.title[0..15] + '...' } else { entry.title }
		app.ctx.draw_text(20, by + 8, title_trunc, size: 14, color: t.text_primary, bold: true)
		app.ctx.draw_text(20, by + 32, '${entry.date}  ${entry.mood}', size: 12, color: t.text_sec)
	}

	// Draw Sidebar Footer (Exit Button)
	app.ctx.draw_rect_filled(0, app.win_height - 50, app.sidebar_width, 50, t.bg_sidebar)
	app.ctx.draw_line(0, app.win_height - 50, app.sidebar_width, app.win_height - 50, t.border)
	exit_btn_color := if app.hover_exit { gg.rgb(220, 38, 38) } else { gg.rgb(185, 28, 28) }
	app.ctx.draw_rect_filled(20, app.win_height - 40, 210, 30, exit_btn_color)
	app.ctx.draw_text(74, app.win_height - 32, 'Exit Application', size: 12, color: gg.white, bold: true)

	// 2. Draw Main Panel
	app.ctx.draw_rect_filled(app.sidebar_width + 1, 0, app.win_width - app.sidebar_width, app.win_height, t.bg_base)

	if app.mode == .view {
		draw_view_mode(app, t)
	} else {
		draw_form_mode(app, t)
	}

	app.ctx.end()
}

fn on_event(e &gg.Event, mut app App) {
	if e.typ == .mouse_down {
		handle_click(int(e.mouse_x), int(e.mouse_y), mut app)
	} else if e.typ == .mouse_move {
		handle_move(int(e.mouse_x), int(e.mouse_y), mut app)
	} else if e.typ == .char {
		handle_char(e.char_code, mut app)
	} else if e.typ == .key_down {
		if e.key_code == .q && (e.modifiers & u32(gg.Modifier.super)) != 0 {
			app.ctx.quit()
			return
		}
		handle_key(e.key_code, mut app)
	} else if e.typ == .mouse_scroll {
		handle_scroll(e, mut app)
	}
}

fn main() {
	mut app := &App{
		hover_moods: []bool{len: 7, init: false}
	}
	app.entries = read_entries_from_file()
	is_dark, w, h := read_settings_from_file()
	app.is_dark_mode = is_dark
	app.win_width = w
	app.win_height = h
	if app.entries.len > 0 {
		app.selected_index = 0
	}
	
	mut font_path := ''
	$if darwin {
		fallback_fonts := [
			'/System/Library/Fonts/Supplemental/Arial.ttf',
			'/System/Library/Fonts/Geneva.ttf',
			'/System/Library/Fonts/SFNSMono.ttf',
			'/System/Library/Fonts/Helvetica.ttc',
		]
		for f in fallback_fonts {
			if os.exists(f) {
				font_path = f
				break
			}
		}
	}

	app.ctx = gg.new_context(
		bg_color:     gg.rgb(20, 20, 25)
		width:        app.win_width
		height:       app.win_height
		window_title: 'MindSpace Journal'
		user_data:    app
		frame_fn:     on_frame
		event_fn:     on_event
		font_path:    font_path
	)
	
	app.ctx.run()
}
