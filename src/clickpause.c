/* SPDX-License-Identifier: LGPL-2.1-or-later */

#define VLC_MODULE_LICENSE VLC_LICENSE_LGPL_2_1_PLUS
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_actions.h>
#include <vlc_filter.h>
#include <vlc_mouse.h>

static int Open(vlc_object_t *object);

vlc_module_begin()
    set_shortname("Click to pause/play")
    set_description("Click to pause/play")
    set_help("Toggle playback with a left click on the video image. "
             "Enable or disable this filter in Preferences > All > Video > Filters.")
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VFILTER)
    set_capability("video filter", 0)
    set_callbacks(Open, NULL)
vlc_module_end()

static picture_t *Filter(filter_t *filter, picture_t *picture)
{
    (void)filter;
    return picture;
}

static int Mouse(filter_t *filter, vlc_mouse_t *output,
                 const vlc_mouse_t *previous, const vlc_mouse_t *current)
{
    /* Preserve mouse events for VLC and the other filters. */
    *output = *current;

    const video_format_t *format = &filter->fmt_out.video;
    const int64_t x = (int64_t)current->i_x - format->i_x_offset;
    const int64_t y = (int64_t)current->i_y - format->i_y_offset;

    if (vlc_mouse_HasPressed(previous, current, MOUSE_BUTTON_LEFT)
        && x >= 0 && x < format->i_visible_width
        && y >= 0 && y < format->i_visible_height)
    {
        /* Use the same action as VLC's play/pause hotkey, including its OSD.
         * Mouse callbacks also run while the video is paused. */
#ifdef HAVE_VLC_OBJECT_MEMBERS
        libvlc_int_t *instance = filter->obj.libvlc;
#else
        libvlc_int_t *instance = filter->p_libvlc;
#endif
        var_SetInteger(instance, "key-action", ACTIONID_PLAY_PAUSE);
    }

    return VLC_SUCCESS;
}

static int Open(vlc_object_t *object)
{
    filter_t *filter = (filter_t *)object;

    if (!es_format_IsSimilar(&filter->fmt_in, &filter->fmt_out))
        return VLC_EGENERIC;

    filter->pf_video_filter = Filter;
    filter->pf_video_mouse = Mouse;
    return VLC_SUCCESS;
}
