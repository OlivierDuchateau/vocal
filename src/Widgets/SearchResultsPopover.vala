/***
  BEGIN LICENSE

  Copyright (C) 2014-2015 Nathan Dyer <mail@nathandyer.me>
  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as
  published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program.  If not, see <http://www.gnu.org/licenses>

  END LICENSE
***/

using Gtk;

namespace Vocal {
	public class SearchResultsPopover : Gtk.Popover {

		public signal void show_full_results();
		public signal void episode_selected(Podcast podcast, Episode episode);
		public signal void podcast_selected(Podcast podcast);
		public signal void subscribe_to_podcast(string itunes_url);

		public Gee.ArrayList<Podcast> p_matches;
		public Gee.ArrayList<Episode> e_matches;
		public Gee.ArrayList<DirectoryEntry> c_matches;

		public Gtk.Button full_results_button;

		private Gee.ArrayList<Widget> local_episodes_widgets;
		private Gee.ArrayList<Widget> local_podcasts_widgets;
		private Gee.ArrayList<Widget> cloud_results_widgets;

	    private Gtk.ListBox local_episodes_listbox;
		private Gtk.ListBox local_podcasts_listbox;
		private Gtk.ListBox cloud_results_listbox;

		private Library library;
		private iTunesProvider itunes;

		Gtk.Box		content_box;

		private const string 	cloud_provider = "iTunes";
		private string query;

		private bool update_complete = true;
		private GLib.Cancellable cancellable;

		private bool updating_results_UI = false;
		private bool additional_update_pending = false;

		/*
		 * Constructor for the shownotes popover relative to a given parent
		 */
		public SearchResultsPopover(Gtk.Widget parent, Library library) {
			this.set_relative_to(parent);
			this.library = library;
			this.itunes = new iTunesProvider();
			this.width_request = 600;
			initialize();
		}


		/*
		 * Set the current query
		 */
		public void set_query(string query) {
			this.query = query;
			on_query_update();
		}
	

		/*
		 * Called whenever the text query changes. Finds new matches given the search terms
		 * and displays them back to the user.
		 */
		public async void on_query_update() {

			// If the previous update isn't complete
			if(!update_complete) {
				cancellable.cancel();
				update_complete = true;
			}

			SourceFunc callback = on_query_update.callback;

            ThreadFunc<void*> run = () => {

        		update_complete = false;

				if(query.length > 0) {

					p_matches.clear();
					p_matches.add_all(library.find_matching_podcasts(query));

					e_matches.clear();
					e_matches.add_all(library.find_matching_episodes(query));

					cancellable.cancelled.connect(() => {
						return;
					});

					c_matches.clear();
					c_matches.add_all(itunes.search_by_term(query, 3));
				}

				update_complete = true;
				

				Idle.add((owned) callback);
                return null;
            };

            Thread.create<void*>(run, false);
            yield;

            update_search_view();
		}


        private void initialize() {
            local_episodes_widgets = new Gee.ArrayList<Widget>();
            local_podcasts_widgets = new Gee.ArrayList<Widget>();
            cloud_results_widgets = new Gee.ArrayList<Widget>();

            p_matches = new Gee.ArrayList<Podcast>();
            e_matches = new Gee.ArrayList<Episode>();
            c_matches = new Gee.ArrayList<DirectoryEntry>();
        }

		/*
		 * Called when the search update is complete and the new matches
		 * are ready to be displayed to the user
		 */
		private async void update_search_view() {

			SourceFunc callback = update_search_view.callback;

            ThreadFunc<void*> run = () => {

            	if(!updating_results_UI) {

	            	updating_results_UI = true;

		    		local_episodes_listbox = new Gtk.ListBox();
					local_podcasts_listbox = new Gtk.ListBox();
					cloud_results_listbox = new Gtk.ListBox();

					local_episodes_listbox.activate_on_single_click = true;
					local_podcasts_listbox.activate_on_single_click = true;
					cloud_results_listbox.activate_on_single_click = true;
					cloud_results_listbox.selection_mode = Gtk.SelectionMode.NONE;

					local_episodes_listbox.button_press_event.connect(on_episode_activated);
					local_podcasts_listbox.button_press_event.connect(on_podcast_activated);

					local_episodes_widgets.clear();
					local_podcasts_widgets.clear();
					cloud_results_widgets.clear();

					var local_episodes_label = new Gtk.Label(_("Episodes from Your Library"));
					var local_podcasts_label = new Gtk.Label(_("Podcasts from Your Library"));
					var cloud_results_label = new Gtk.Label(_("%s Podcast Results".printf(cloud_provider)));

					local_episodes_label.get_style_context().add_class("h4");
					local_episodes_label.set_property("xalign", 0);
					local_podcasts_label.get_style_context().add_class("h4");
					local_podcasts_label.set_property("xalign", 0);
					cloud_results_label.get_style_context().add_class("h4");
					cloud_results_label.set_property("xalign", 0);

					full_results_button = new Gtk.Button.with_label(_("View All Results"));
					full_results_button.get_style_context().add_class("suggested-action");
					this.can_focus = false;
					full_results_button.can_focus = false;

					full_results_button.clicked.connect(() => {
						show_full_results();
					});

					for(int i = 0; i < 5; i++) {
						if(i < p_matches.size) {
							SearchResultBox srb = new SearchResultBox(p_matches[i], null);
							local_podcasts_widgets.add(srb);
							local_podcasts_listbox.add(srb);
						}
					}
					if(p_matches.size < 1) {
						var no_matches_label = new Gtk.Label(_("No matches found."));
						local_podcasts_widgets.add(no_matches_label);
						local_podcasts_listbox.add(no_matches_label);
					}

					for(int i = 0; i < 5; i++) {
						if(i < e_matches.size) {
							Podcast parent = null;
							foreach(Podcast p in library.podcasts) {
								if(e_matches[i].parent.name == p.name) {
									parent = p;
								}
							}
							SearchResultBox srb = new SearchResultBox(parent, e_matches[i]);
							local_episodes_widgets.add(srb);
							local_episodes_listbox.add(srb);
						}
					}
					if(e_matches.size < 1) {
						var no_matches_label = new Gtk.Label(_("No matches found."));
						local_episodes_widgets.add(no_matches_label);
						local_episodes_listbox.add(no_matches_label);
					}

					for(int i = 0; i < 5; i++) {
						if(i < c_matches.size) {
							Podcast p_temp = new Podcast();
							p_temp.name = c_matches[i].title;
							p_temp.local_art_uri = c_matches[i].artworkUrl600;
							SearchResultBox srb = new SearchResultBox(p_temp, null, c_matches[i].summary, c_matches[i].itunesUrl);
							srb.subscribe_to_podcast.connect((itunes_url) => {
								subscribe_to_podcast(itunes_url);
							});
							cloud_results_widgets.add(srb);
							cloud_results_listbox.add(srb);
						}
					}
					if(c_matches.size < 1) {
						var no_matches_label = new Gtk.Label(_("No matches found."));
						cloud_results_widgets.add(no_matches_label);
						cloud_results_listbox.add(no_matches_label);
					}

					if(content_box != null) {
		    			content_box.destroy();
		    			content_box = null;
		    		}

					content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
					this.add(content_box);
					content_box.add(local_podcasts_label);
					content_box.add(local_podcasts_listbox);
					content_box.add(local_episodes_label);
					content_box.add(local_episodes_listbox);
					content_box.add(cloud_results_label);
					content_box.add(cloud_results_listbox);
					content_box.add(full_results_button);

					content_box.margin = 5;

					show_all();
				}

				Idle.add((owned) callback);
	                return null;
            };

            Thread.create<void*>(run, false);
            yield;

            updating_results_UI = false;

            if(additional_update_pending) {
            	update_search_view();
            }
		}


		/*
		 * Called whenever a user clicks on an matched episode
		 */
		private bool on_episode_activated(Gdk.EventButton button) {
			var row = local_episodes_listbox.get_row_at_y((int)button.y);
			int index = row.get_index();
			SearchResultBox selected = local_episodes_widgets[index] as SearchResultBox;
			episode_selected(selected.get_podcast(), selected.get_episode());
			return false;
		}
		

		/*
		 * Called whenever a user clicks on a matched podcast
		 */
		private bool on_podcast_activated(Gdk.EventButton button) {
			var row = local_podcasts_listbox.get_row_at_y((int)button.y);
			int index = row.get_index();
			SearchResultBox selected = local_podcasts_widgets[index] as SearchResultBox;
			podcast_selected(selected.get_podcast());
			return false;
		}
		
		/*
		 * Tells the popover about the status of adding a podcast
		 * so it can update the icon
		 */
		 public void add_status_changed(bool successfully_added, string? name = null) {
			 if(successfully_added) {
				 foreach(Widget w in cloud_results_widgets) {
					 var srb = (SearchResultBox) w;
					 
					 // compare the names if possible
					 if(name != null) {
						 if(name == srb.get_podcast().name) {
							 srb.set_button_icon("emblem-ok-symbolic");
						 }
					 } else {
						 srb.set_button_icon("emblem-ok-symbolic");
					 }
				 }
			 } else {
				 foreach(Widget w in cloud_results_widgets) {
					 var srb = (SearchResultBox) w;
					 
					 // compare the names if possible
					 if(name != null) {
						 if(name == srb.get_podcast().name) {
							 srb.set_button_icon("list-add-symbolic");
						 }
					 } else {
						 srb.set_button_icon("list-add-symbolic");
					 }
				 }
			 }
		 }
  	}
}
