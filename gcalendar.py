#!/usr/bin/python -W ignore::DeprecationWarning

"""
This script interfaces with Google calendar.

For usage and help:

    gcalendar.py -h              # Brief usage and list of options
    gcalendar.py --full-help     # Full help including examples and notes
"""
# W0404: *Reimport %r (imported line %s)*
# pylint: disable=W0404
from copy import copy
from optparse import Option, OptionParser, OptionValueError
import atom
import atom.service
import filecmp
import gdata.calendar
import gdata.calendar.service
import gdata.service
import getpass
import logging
import netrc
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

CALENDAR_MACRO = 'calendar_account'
CALENDAR_URL = 'www.google.com/calendar/feeds/default/private/full'
P_ID = re.compile(r'^http://{url}/(.*)$'.format(url=CALENDAR_URL))
P_REMINDER = re.compile(r'^(.*) minutes by (.*)$')
TMP_DIR = '/tmp/calendar'

logging.basicConfig(level=logging.WARN,
    stream=sys.stdout,
    format='%(levelname)-8s %(message)s',
    )
LOG = logging.getLogger('')


class Calendar():
    """Class representing a Google calendar. """
    def __init__(self, gd_client=None):
        self.gd_client = gd_client
        self.query = gdata.calendar.service.CalendarEventQuery('default',
            'private', 'full')
        self.query.max_results = 999999
        self.feed = None         # Set in get(), query may change
        self.events = []
        self.filtered_events = []
        self.filename = ''
        self.in_fmt = '%Y-%m-%d %H:%M:%S'
        self.start_fmt = '%Y-%m-%dT%H:%M:%S.0500Z'

    def add_blank_event(self):
        """Adds a blank event using Google's Calendar API
        Returns:
            Event instance, if successful. None, otherwise.
        """
        LOG.debug("Adding blank event.")
        if not self.gd_client:
            return
        new_event = gdata.calendar.CalendarEventEntry(title=atom.Title(
            text='_new_event'))
        event_entry = None
        try:
            event_entry = self.gd_client.InsertEvent(new_event,
                '/calendar/feeds/default/private/full')
        except gdata.service.RequestError, e:
            msg = 'Add blank event failed'
            if 'reason' in e[0]:
                reason = e[0]['reason']
                if e[0]['reason'] == 'Conflict':
                    reason = 'event conflicts with existing event'
                msg = '{msg}: {reason}'.format(msg=msg, reason=reason)
            print >> sys.stderr, msg
        return Event(entry=event_entry)

    def edit(self):
        """Edit calendar events"""
        # Create temp file.
        if not os.path.exists(TMP_DIR):
            os.makedirs(TMP_DIR)

        (unused_tmp_file_h, tmp_filename) = tempfile.mkstemp(dir=TMP_DIR)
        bak_tmp_name = '{tmp}.bak'.format(tmp=tmp_filename)

        # Get calendar events into temp file.
        old_stdout = sys.stdout
        sys.stdout = open(tmp_filename, 'w')
        self.print_events()
        sys.stdout = old_stdout

        # Back up file
        # copy2 is used to preserve meta data
        shutil.copy2(tmp_filename, bak_tmp_name)

        # Edit file with vim
        subprocess.call(['vim', tmp_filename])

        # Diff file and backup
        if not filecmp.cmp(tmp_filename, bak_tmp_name):
            self.filename = tmp_filename

    def event_attributes(self, info):
        """Creates a dictionary of event attributes from contents in a file
        Args:
            info: list, lines of event info
        Returns:
            Dictionary: dictionary with keys: id, what, when, until, where,
                description, remind

            Example: {
                     'id': 'h1vqotvj45rmkaf86rr7cru8cc',
                     'what': 'Dentist Appointment',
                     'when': '2011-06-13 09:20:00',
                     'until': '2011-06-13 10:20:00',
                     'where': '123 Main St Mytown ON A1A 1A1',
                     'description': 'Dr. Dennis Dentist Phone: (111) 555-2121',
                     'remind': '60 minutes by sms',
                     }
        """
        # R0201: *Method could be a function*
        # pylint: disable=R0201
        LOG.debug("Parsing info and creating attributes dictionary.")
        attributes = {}
        ## Adapted from OPTCRE in ConfigParser.py
        item_re = re.compile(
            r'(?P<key>[^:\s][^:]*)'               # very permissive!
            r'\s*(?P<vi>[:])\s*'                  # any number of space/tab,
                                                  # followed by separator
                                                  # (:), followed
                                                  # by any # space/tab
            r'(?P<value>.*)$'                     # everything up to eol
            )

        for line in info:
            mo = item_re.match(line)
            if mo:
                item_key, unused_vi, item_value = mo.group('key', 'vi',
                        'value')
                if item_key == 'remind':
                    if not item_key in attributes:
                        attributes[item_key] = []
                    attributes[item_key].append(item_value)
                else:
                    attributes[item_key] = item_value
        return attributes

    def filter(self, keyword=None, match_id=None):
        """ Filter events keeping only those that qualify.
        Args:
            keyword: string, keyword to match on
            match_id: string, id to match on

        Notes:
            If a match_id is provided, the keyword is ignored.

            Keyword matching: events which contain the provided keyword in the
            "what" or "description" are considers a match. Matching is case
            insensitive. If no keyword is provided all events match.
        """
        LOG.debug("Filtering events for keyword: {kw}".format(kw=keyword))

        if not keyword and not match_id:
            LOG.debug("No keyword or id, no events filtered")
            self.filtered_events = self.events
            return

        self.filtered_events = []
        for event in self.events:
            id_match = True
            if match_id and event.id != match_id:
                id_match = False
            if event.is_match(keyword=keyword) and id_match:
                self.filtered_events.append(event)

    def get(self):
        """Get events from google calendar."""
        self.feed = self.gd_client.CalendarQuery(self.query)
        self.events = []
        for entry in self.feed.entry:
            event = Event(entry=entry)
            self.events.append(event)

    def print_events(self, mode='long', sort_by='when'):
        """ Print events.
        Args:
            mode: string, print format mode, one of 'long', 'short'
            sort_by: string, attribute to sort events by, one of
                'id', 'what', 'where', 'when', 'until', 'description'

        Example output:

        ## Mode: long

        id: 8d3g6ifa8qbdjpi74vv34i5s8s
        what: Blades hockey game
        when: 2010-01-03 10:00:00
        until: 2010-01-03 11:00:00
        where: Cavan St, Palmerston, ON
        description: Play hockey in the Sunday league.

        ## Mode: short

        2010-01-03 10:00:00 Blades hockey game

        """
        printable_item = []
        for event in self.filtered_events:
            # The tilde char sorts after alpha numeric characters. By
            # defaulting the sort key to start with tilde, any events without a
            # value in the sort_by field will sort to the end of the list.
            # The event.id is appended to the sort key so that each key is
            # unique. This will enforce a specific order so results will always
            # be consistent.
            sort_key = ''.join(('~n/a~', event.id))
            if sort_by and getattr(event, sort_by):
                sort_key = str(getattr(event, sort_by)).lower()
            e = {
                    'id': event.id,
                    'what': event.what,
                    'when': event.when,
                    'until': event.until,
                    'where': event.where,
                    'description': event.description,
                    'sort_key': sort_key,
                    'reminders': event.reminders,
                    }
            printable_item.append(e)

        cmp_fn = lambda x, y: cmp(x['sort_key'], y['sort_key'])

        for printable in sorted(printable_item, cmp=cmp_fn):
            if mode == 'short':
                print '{when}\t{what}'.format(when=printable['when'],
                    what=printable['what'])
            else:
                print ""
                fields = ['id', 'what', 'when', 'until', 'where',
                    'description']
                for field in fields:
                    if printable[field]:
                        print '{field}: {prt}'.format(field=field,
                            prt=printable[field])
                if printable['reminders']:
                    for reminder in printable['reminders']:
                        print 'remind: {rem}'.format(rem=reminder)

    def set_query_filters(self, from_date=None, to_date=None):
        """Set query filters.
        Args:
            from_date, string, date, 'yyyy-mm-dd'
            to_date, string, date, 'yyyy-mm-dd'
        """
        if from_date:
            dt = time.strptime("{date} 00:00:00".format(date=from_date),
                self.in_fmt)
        else:
            dt = time.localtime()       # Today
        self.query.start_min = time.strftime(self.start_fmt,
            time.gmtime(time.mktime(dt)))

        if to_date:
            dt = time.strptime("{date} 23:59:59".format(date=to_date),
                self.in_fmt)
            self.query.start_max = time.strftime(self.start_fmt,
                time.gmtime(time.mktime(dt)))

    def update(self):
        """Update events from file. """
        if not self.filename:
            return
        for info in self.update_generator():
            if not self.update_event(info):
                print >> sys.stderr, 'Calendar event update failed:'
                print >> sys.stderr, info
        return

    def update_event(self, info):
        """Update calendar event with provided information.

        Args:
            info: list, list of strings of information data
        """
        attributes = self.event_attributes(info)
        if not attributes:
            return

        action = None
        if 'id' in attributes.keys():
            if 'what' in attributes.keys() and attributes['what'] == 'DELETE':
                action = 'delete'
            else:
                action = 'update'
        else:
            action = 'add'

        if action == 'add':
            # Add a blank event and then continue as if updating.
            event = self.add_blank_event()
            self.events.append(event)
            if event.entry.id:
                match = P_ID.match(event.entry.id.text)
                if match:
                    attributes['id'] = match.group(1)
            action = 'update'

        # Find the matching event
        event = None
        for e in self.events:
            match = P_ID.match(e.entry.id.text)
            if match:
                if attributes['id'] == match.group(1):
                    event = e
        if not event:
            return

        label = ''
        if 'what' in attributes:
            label = attributes['what']
        elif 'description' in attributes:
            label = attributes['description']
        else:
            label = attributes['id']
        action_labels = {
            'add': 'Adding',
            'delete': 'Deleting',
            'update': 'Updating',
            }
        LOG.info("{action}: {label}".format(action=action_labels[action],
                label=label))

        if action == 'delete':
            return self.gd_client.DeleteEvent(event.entry.GetEditLink().href)

        entry = event.entry
        entry.title = None
        if 'what' in attributes:
            entry.title = atom.Title(text=attributes['what'])

        entry.when = []
        if 'when' in attributes:

            ## Convert from yyyy-mm-dd hh:mm:ss to googles format
            in_fmt = '%Y-%m-%d %H:%M:%S'
            out_fmt = '%Y-%m-%dT%H:%M:%S.000Z'
            dt = time.strptime(attributes['when'], in_fmt)
            start_time = time.strftime(out_fmt, time.gmtime(time.mktime(dt)))
            end_time = None
            if 'until' in attributes:
                dt = time.strptime(attributes['until'], in_fmt)
                end_time = time.strftime(out_fmt, time.gmtime(time.mktime(dt)))
            entry.when.append(gdata.calendar.When(start_time=start_time,
                end_time=end_time))

            if 'remind' in attributes:
                reminders = []
                for reminder in attributes['remind']:
                    match = P_REMINDER.match(reminder)
                    if match:
                        minutes = match.group(1)
                        method = match.group(2)
                        reminders.append(
                                gdata.calendar.Reminder(method=method,
                                    minutes=minutes)
                                )
                    else:
                        LOG.error("Reminder: {var}. Invalid format.".format(
                            var=reminder))
                entry.when[0].reminder = reminders

        entry.where = []
        if 'where' in attributes:
            entry.where.append(
                gdata.calendar.Where(value_string=attributes['where']))

        entry.content = None
        if 'description' in attributes:
            entry.content = atom.Content(text=attributes['description'])

        result = None
        for unused_count in range(1, 15):
            try:
                result = self.gd_client.UpdateEvent(entry.GetEditLink().href,
                    entry)
            except gdata.service.RequestError, error:
                e = error.args[0]
                LOG.error("RequestError: " + time.strftime(
                        '%Y-%m-%d %H:%M:%S', time.localtime()))
                LOG.error("Status: %s, %s" % (e['status'], e['reason']))
                LOG.error("Pausing a few seconds before trying again.")
                time.sleep(1)
            if result:
                break
        return result

    def update_generator(self):
        """Generator bundling lines of info for a single calendar"""
        lines = []
        with open(self.filename) as f:
            for line in f:
                if len(line.strip()) == 0:
                    if len(lines) > 0:
                        yield lines
                    lines = []
                else:
                    lines.append(line.strip())
            if len(lines) > 0:
                yield lines


class Event():
    """
    This class pseudo extends gdata.calendar.CalendarEventEntry. The entry
    property points to a CalendarEventEntry object.
    """
    # C0103: *Invalid name "%s" (should match %s)*
    # pylint: disable=C0103
    def __init__(self, entry=None):
        self.entry = entry
        self.id = None
        self.set_id()
        self.what = self.entry.title.text
        self.when = None
        self.until = None
        self.set_when()
        self.where = None
        self.set_where()
        self.description = self.entry.content.text
        self.reminders = []
        self.set_reminders()

    def format_time(self, timestamp):
        """
        Convert time from google format, eg '2010-01-03T10:00:00.000-05:00'
        to our format yyyy-mm-dd hh:mm:ss

        """
        # R0201: *Method could be a function*
        # pylint: disable=R0201
        datetime_fmt = '%Y-%m-%d %H:%M:%S'
        iso8601 = Iso8601(timestamp=timestamp)
        return time.strftime(datetime_fmt, time.localtime(iso8601.parse()))

    def is_match(self, keyword=None):
        """Determine if event is a match for keyword.
        Args:
            keyword: string, keyword to match on
        Returns:
            True if event is a match.
        Notes:
            The keyword is matched againse the event what and description.
            Matching is case insensitive.
        """
        if not keyword:
            return True
        match = False
        if self.what:
            if re.search(keyword, self.what, re.IGNORECASE):
                match = True
        if self.description:
            if re.search(keyword, self.description, re.IGNORECASE):
                match = True
        return match

    def set_id(self):
        """Set the id property of the event instance. """
        if self.entry.id:
            match = P_ID.match(self.entry.id.text)
            if match:
                self.id = match.group(1)

    def set_reminders(self):
        """Set the reminders property of the event instance."""
        if not self.entry.when:
            return
        if not len(self.entry.when) > 0:
            return
        if not hasattr(self.entry.when[0], 'reminder'):
            return
        if not len(self.entry.when[0].reminder) > 0:
            return
        for reminder in self.entry.when[0].reminder:
            method = reminder.method
            minutes = reminder.minutes
            self.reminders.append('{min} minutes by {method}'.format(
                    min=minutes, method=method))

    def set_when(self):
        """Set the when property of the event instance."""
        if not self.entry.when:
            return
        if not len(self.entry.when) > 0:
            return
        self.when = self.format_time(self.entry.when[0].start_time)
        self.until = self.format_time(self.entry.when[0].end_time)

    def set_where(self):
        """Set the where property of the event instance."""
        if self.entry.where:
            if len(self.entry.where) > 0:
                self.where = self.entry.where[0].value_string


class Iso8601():
    """This class represents an ISO-8601 formatted date/timestamp.

    The code in this class was extracted/adapted from
    _xmlplus/utils/iso8601.py. The header doc from that module is:

        ISO-8601 date format support, sufficient for the profile defined in
        <http://www.w3.org/TR/NOTE-datetime>.

        The parser is more flexible on the input format than is required to
        support the W3C profile, but all accepted date/time values are legal
        ISO 8601 dates. The tostring() method only generates formatted dates
        that are conformant to the profile.

        This module was written by Fred L. Drake, Jr. <fdrake@acm.org>.

    """
    # C0103: *Invalid name "%s" (should match %s)*
    # pylint: disable=C0103
    __date_re = ("(?P<year>\d\d\d\d)"
                 "(?:(?P<dsep>-|)"
                    "(?:(?P<julian>\d\d\d)"
                      "|(?P<month>\d\d)(?:(?P=dsep)(?P<day>\d\d))?))?")
    __tzd_re = "(?P<tzd>[-+](?P<tzdhours>\d\d)(?::?(?P<tzdminutes>\d\d))|Z)"
    __tzd_rx = re.compile(__tzd_re)
    __time_re = ("(?P<hours>\d\d)(?P<tsep>:|)(?P<minutes>\d\d)"
                 "(?:(?P=tsep)(?P<seconds>\d\d(?:[.,]\d+)?))?"
                 + __tzd_re)

    __datetime_re = '{date}(?:T{time})?'.format(date=__date_re, time=__time_re)
    __datetime_rx = re.compile(__datetime_re)

    def __init__(self, timestamp=None):
        """Constructor

        Args
            timestamp - ISO-8601 date/time string
        """
        self.timestamp = timestamp
        return

    def parse(self):
        """Parse an ISO-8601 date/time string, returning the value in seconds
        since the epoch."""
        if not self.timestamp:
            return
        s = self.timestamp
        m = self.__datetime_rx.match(s)
        if m is None or m.group() != s:
            raise ValueError(
                "unknown or illegal ISO-8601 date format: " + repr(s))
        gmt = self.__extract_date(m) + self.__extract_time(m) + (0, 0, 0)
        return time.mktime(gmt) + self.__extract_tzd(m) - time.timezone

    def parse_timezone(self, timezone):
        """Parse an ISO-8601 time zone designator, returning the value in
        seconds relative to UTC.
        """
        m = self.__tzd_rx.match(timezone)
        if not m:
            raise ValueError("unknown timezone specifier: " + repr(timezone))
        if m.group() != timezone:
            raise ValueError("unknown timezone specifier: " + repr(timezone))
        return self.__extract_tzd(m)

    def tostring(self, t, timezone=0):
        """Format a time in ISO-8601 format.

        If `timezone' is specified, the time will be specified for that
        timezone, otherwise for UTC.

        Some effort is made to avoid adding text for the 'seconds' field, but
        seconds are supported to the hundredths.
        """
        if type(timezone) is type(''):
            timezone = self.parse_timezone(timezone)
        else:
            timezone = int(timezone)
        if timezone:
            sign = (timezone < 0) and "+" or "-"
            timezone = abs(timezone)
            hours = timezone / (60 * 60)
            minutes = (timezone % (60 * 60)) / 60
            tzspecifier = '{sign}{hrs:02d}:{mins:02d}'.format(sign=sign,
                hrs=hours, mins=minutes)
        else:
            tzspecifier = "Z"
        psecs = t - int(t)
        t = time.gmtime(int(t) - timezone)
        year, month, day, hours, minutes, seconds = t[:6]
        if seconds or psecs:
            if psecs:
                psecs = int(round(psecs * 100))
                f = ('{yr:04d}-{mth:02d}-{day:02d}'
                     'T{hrs:02d}:{mins:02d}:{secs:02d}.{psecs:02d}{tz}')
                v = dict(yr=year, mth=month, day=day, hrs=hours, mins=minutes,
                    secs=seconds, psecs=psecs, tz=tzspecifier)
                return f.format(**v)
            else:
                f = ('{yr:04d}-{mth:02d}-{day:02d}'
                     'T{hrs:02d}:{mins:02d}:{secs:02d}{tz}')
                v = dict(yr=year, mth=month, day=day, hrs=hours, mins=minutes,
                    secs=seconds, tz=tzspecifier)
                return f.format(**v)
        else:
            f = ('{yr:04d}-{mth:02d}-{day:02d}'
                 'T{hrs:02d}:{mins:02d}{tz}')
            v = dict(yr=year, mth=month, day=day, hrs=hours, mins=minutes,
                tz=tzspecifier)
        return f.format(**v)

    def ctime(self, t):
        """Similar to time.ctime(), but using ISO-8601 format."""
        return self.tostring(t, time.timezone)

    def __extract_date(self, m):
        """Extract date."""
        year = int(m.group("year"))
        julian = m.group("julian")
        if julian:
            return self.__find_julian(year, int(julian))
        month = m.group("month")
        day = 1
        if month is None:
            month = 1
        else:
            month = int(month)
            if not 1 <= month <= 12:
                raise ValueError("illegal month number: " + m.group("month"))
            else:
                day = m.group("day")
                if day:
                    day = int(day)
                    if not 1 <= day <= 31:
                        raise ValueError(
                            "illegal day number: " + m.group("day"))
                else:
                    day = 1
        return year, month, day

    def __extract_time(self, m):
        """Extract time."""
        # R0201: *Method could be a function*
        # pylint: disable=R0201
        if not m:
            return 0, 0, 0
        hours = m.group("hours")
        if not hours:
            return 0, 0, 0
        hours = int(hours)
        if not 0 <= hours <= 23:
            raise ValueError("illegal hour number: " + m.group("hours"))
        minutes = int(m.group("minutes"))
        if not 0 <= minutes <= 59:
            raise ValueError("illegal minutes number: " + m.group("minutes"))
        seconds = m.group("seconds")
        if seconds:
            seconds = float(seconds)
            if not 0 <= seconds <= 60:
                raise ValueError(
                    "illegal seconds number: " + m.group("seconds"))
            # Python 2.3 requires seconds to be an integer
            seconds = int(seconds)
        else:
            seconds = 0
        return hours, minutes, seconds

    def __extract_tzd(self, m):
        """Return the Time Zone Designator as an offset in seconds from UTC."""
        # R0201: *Method could be a function*
        # pylint: disable=R0201
        if not m:
            return 0
        tzd = m.group("tzd")
        if not tzd:
            return 0
        if tzd == "Z":
            return 0
        hours = int(m.group("tzdhours"))
        minutes = m.group("tzdminutes")
        if minutes:
            minutes = int(minutes)
        else:
            minutes = 0
        offset = (hours * 60 + minutes) * 60
        if tzd[0] == "+":
            return -offset
        return offset

    def __find_julian(self, year, julian):
        """Find julian date."""
        # R0201: *Method could be a function*
        # pylint: disable=R0201
        month = julian / 30 + 1
        day = julian % 30 + 1
        jday = None
        while jday != julian:
            t = time.mktime((year, month, day, 0, 0, 0, 0, 0, 0))
            jday = time.gmtime(t)[-2]
            diff = abs(jday - julian)
            if jday > julian:
                if diff < day:
                    day = day - diff
                else:
                    month = month - 1
                    day = 31
            elif jday < julian:
                if day + diff < 28:
                    day = day + diff
                else:
                    month = month + 1
        return year, month, day


def check_date(unused_option, opt, value):
    """ Verify value is a date. Used to validate custom optparser "date" type.
    Args:
        unused_option: optparse Option object
        opt: option string, eg "-f"
        value: date value
    Returns:
        value: date value
    """
    try:
        time.strptime(value, '%Y-%m-%d')
    except ValueError, msg:
        raise OptionValueError(
            'option {opt}: invalid {val}, {msg}'.format(opt=opt, val=value,
                msg=msg))
    return value


def get_email_address():
    """ Get the google email address associated with Google calendar.
    Args:
        None
    Returns:
        email address: myusername@gmail.com
    """
    try:
        net_rc = netrc.netrc()
    except IOError as err:
        LOG.debug('Unable to read $HOME/.netrc file. {reason}'.format(
                    reason=str(err)))
        net_rc = None
    if net_rc:
        try:
            return net_rc.macros[CALENDAR_MACRO][0].strip()
        except KeyError as err:
            msg = ' '.join([
                'Unable to get calendar account from $HOME/.netrc file.',
                'A macdefs "{macro}" is not defined.'.format(
                    macro=CALENDAR_MACRO),
                ])
            LOG.debug(msg)

    # If we are in interactive mode, prompt for password
    psi = os.environ.get('PS1', None)
    if not psi:
        return None
    return raw_input('Email account: ')


def get_password(email_address):
    """ Get google email account password.
    Args:
        email_address: myusername@gmail.com
    Returns:
        password (string)
    Notes:
        If a password is not accessible, the user is prompted for one.
    """
    try:
        net_rc = netrc.netrc()
    except IOError as err:
        LOG.debug('Unable to read $HOME/.netrc file. {reason}'.format(
                    reason=str(err)))
    if net_rc:
        for host in net_rc.hosts.keys():
            if net_rc.authenticators(host)[0] == email_address:
                return net_rc.authenticators(host)[2]

    # If we are in interactive mode, prompt for password
    psi = os.environ.get('PS1', None)
    if not psi:
        return None
    return getpass.getpass()


def usage_full():
    """Return a string representing the full usage text."""

    return """

OVERVIEW:

    This script permits listing, creating, editing and deleting of
    google calendar events.


OPTIONS:

    -a, --account
        The account option is used to indicate the gmail account to use for
        calendar events. The option expects an email address.

            gcalendar.py --account username@gmail.com

    -e, --edit
        Edit calendar events. By default events are printed to stdout. The edit
        option permits creating, updating and deleting calendar events.

    -f --from-date
        Print or edit calendar events from this date onward. By default
        the calendar events printed or edited start from today's date.
        The --from-date allows the user to access events from a date in
        the past or a date in the future. Date format is yyyy-mm-dd.

    --full-help
        Print this full help and exit. Full help includes examples and notes.

    -i, --id
        Print or edit a single calendar event identified by the given
        id.

    -m, --mode
        The mode option indicates the format of the printed output. The
        default is 'long'.
            Choices:
                long        mulitiple lines per event, one line per attribute
                short       one line per event

    -s, --sort,
        The sort option indicates how to sort calendar events when
        printed or edited.
            Choices:
                id              sort by calendar event id
                what            sort by calendar event what
                where           sort by calendar event location
                when            sort by calendar event start time
                until           sort by calendar event end time
                description     sort by calendar event description
        The default is 'when'.

    -t --to-date
        Print or edit calendar events up to and including this date. By default
        printing and editing includes all of today's and all future
        caledar events. The --to-date allows the user to limit the
        events to a specific date. Date format is yyyy-mm-dd.

    -v, --verbose,
        Print information messages to stdout.

    --vv
        More verbose. Print debugging messages to stdout.


NOTES:
    To add a calendar evnet, edit events and add an event with no id.

    To delete a calendar event, edit it and change the 'what' attribute to the
    single word DELETE. Uppercase is required.

    When editing calendar events, a list of events is stored in a temp
    file and the file is opened in the vim editor. If you quit without
    saving, no updates are made. If you save, all events in the file
    are updated.

    If changes to only a few events are made, it's possible to speed up the
    update by removing everything from the file but the information for
    the events that are changed.


EVENT ATTRIBUTES:

    id
        Required: Yes, for update and delete, no for adding.
        Format: 43 character hash
        Example: s27q7kplr9jpljftprurg3ro2g
        Notes: The id is provided by google.

    what
        Required: No, but recommended.
        Format: string
        Default: _new_event
        Example: Dentist appointment.

    where
        Required: No
        Format: string
        Default: empty string
        Example: 123 Main St Mytown ON A1B 2C3
        Notes: If an address suitable for google map is used, google
            calendar will provide a link to a google map on the calendar
            page.

    when
        Required: Yes
        Format: yyyy-mm-dd hh:mm:ss
        Example: 2011-01-31 09:00:00

    until
        Required: No
        Format: yyyy-mm-dd hh:mm:ss
        Default: If not provided, is set to value of 'when' attribute.
        Example: 2011-01-31 10:00:00

    description
        Required: No
        Format: string
        Default: empty string
        Example: General dental cleaning with Dr. Doe.'

    remind
        Required: No
        Format:  <integer> minutes by [email|sms|popup]
        Default: empty string
        Example: 60 minutes by sms
        Notes:
            The google calendar account has to be configured for
            some options, eg sms, to work. See calendar settings on
            google page.
            Multiple remind attributes are allowed. For example, the following
            event is configured to send an alert by email one hour before the
            event and five minutes before the event by pager.

                what: My event
                when: 2011-01-31 13:00:00
                remind: 60 minutes by email
                remind: 5 minutes by sms


    With the exception of the 'remind' attribute, each attribute should appear
    at most one time in a calendar event.

    Each attribute of a calendar event must be written on a separate line with
    no blank lines.

    Use blank lines to separate events.

    Keyword matching is case insensitive.


EXAMPLES:
    # Display all calendar events
    gcalendar.py

    # Display calendar events keyword 'dentist'
    gcalendar.py dentist

    # Display all calendar events, short format sorted by "what"
    gcalendar.py -m short -s what

    # Edit calendar events
    gcalendar.py -e

    # Edit dentist appointment
    gcalendar.py -e dentist

    # Edit examples
    # If editing, on saving the folling calendar events, the first event will
    # be updated, the second event will be deleted, and the third event will be
    # created (it has no 'id').

        id: s27q7kplr9jpljftprurg3ro2g
        what: Ultimate Frisbee Game
        when: 2011-02-01 19:00:00
        until: 2011-02-01 19:59:00
        where: Super frisbee fields
        description: Game vs another team.
        remind: 60 minutes by sms

        id: lejpn49oa0njsbr44hqessnmhc
        what: DELETE
        when: 2011-02-05 19:00:00
        until: 2011-02-05 20:30:00
        where: Anothertown ON Z9Y 8W7
        description: Some event.
        remind: 60 minutes by sms

        what: Dentist Appointment
        when: 2011-06-13 09:20:00
        until: 2011-06-13 10:20:00
        where: 123 Main St Sometown ON A1B 2C3
        description: General dental cleaning with Dr. Crest.
        remind: 60 minutes by sms
        remind: 90 minutes by sms


CONFIGURATION:

    Netrc

    Gmail account usernames and passwords can be read from a $HOME/.netrc file.
    Define a machine for the gmail IMAP server and create a macdef to indicate
    the gmail account used for calendars.

        machine imap.gmail.com
            login useraname@gmail.com
            password fluf5yk1tt3ns

        macdef calendar_account
            username@gmail.com


REQUIREMENTS:

    This script is written for python 2.6. The following non-standard python
    modules are required.

        gdata

"""


def main():
    """ Main routine.
    Args:
        None.
    Returns:
        None.
    """

    usage = "usage: %prog [options] [keyword]"
    parser = OptionParser(usage=usage, option_class=MyOption)

    parser.add_option("-a", "--account", dest="account",
        help="The gmail account email address.")
    parser.add_option("-e", "--edit", dest="edit", action="store_true",
        help="Edit calendar events.")
    parser.add_option('-f', '--from-date', dest='from_date', type='date',
        help="Display calendar entries from this date. yyyy-mm-dd")
    parser.add_option('--full-help', dest='full_help',
        action='store_true',
        help='Print full help and exit. Full help includes examples/notes.')
    parser.add_option('-i', '--id', dest='id', type='str',
        help="Id of calendar entry")
    parser.add_option('-m', '--mode', dest='mode',
        choices=('long', 'short'), default='long',
        help="Mode. One of 'short' or 'long' mode. Default 'long'.")
    sort_choices = ('id', 'what', 'where', 'when', 'until', 'description')
    parser.add_option('-s', '--sort', dest='sort',
        choices=sort_choices,
        default='when',
        help=' '.join(['Field to sort by.',
            'One of: {opts}'.format(opts=sort_choices),
            "Default 'when'."]))
    parser.add_option('-t', '--to-date', dest='to_date', type='date',
        help="Display calendar entries up to this date. yyyy-mm-dd")
    parser.add_option("-v", "--verbose",
        action="store_true", dest="verbose", default=False,
        help="Print messages to stdout.")
    parser.add_option('--vv', action='store_const', const=2,
        dest='verbose', help='More verbose.')

    (options, args) = parser.parse_args()

    if options.verbose > 0:
        if options.verbose == 1:
            LOG.setLevel(logging.INFO)
        else:
            LOG.setLevel(logging.DEBUG)

    if options.full_help:
        parser.print_help()
        print
        print usage_full()
        exit(0)

    keyword = None
    if len(args) > 0:
        keyword = args[0]

    if options.account:
        email = options.account
    else:
        email = get_email_address()
    if not email:
        msg = "Unable to determine google email account to login with."
        print >> sys.stderr, msg
        quit(1)

    password = get_password(email)

    LOG.debug("email: {email}".format(email=email))
    LOG.debug("password: {pw}".format(pw=password))

    LOG.debug("Creating google calendar service.")
    gd_client = gdata.calendar.service.CalendarService()

    LOG.debug("Logging in.")
    gd_client.email = email
    gd_client.password = password
    gd_client.source = 'Google-Calendar_Python_Sample-1.0'
    gd_client.ProgrammaticLogin()

    LOG.debug("Getting calendar feed.")

    calendar = Calendar(gd_client=gd_client)
    calendar.set_query_filters(from_date=options.from_date,
        to_date=options.to_date)
    calendar.get()
    calendar.filter(keyword=keyword, match_id=options.id)
    if options.edit:
        # All details are required for edit. Force long mode.
        options.mode = 'long'
    if options.edit:
        LOG.debug("Editing events.")
        calendar.edit()
        calendar.update()
    else:
        LOG.debug("Printing events.")
        calendar.print_events(mode=options.mode, sort_by=options.sort)


class MyOption (Option):
    """ Class overrides optparser Option class. Creates a new "date" option
    type.
    Args:
        None.
    Returns:
        None.
    """
    TYPES = Option.TYPES + ("date",)
    TYPE_CHECKER = copy(Option.TYPE_CHECKER)
    TYPE_CHECKER["date"] = check_date


if __name__ == '__main__':
    main()
