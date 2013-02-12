//
//  OverviewViewController.m
//  pomodorable
//
//  Created by Kyle Kinkade on 11/6/11.
//  Copyright (c) 2011 Monocle Society LLC All rights reserved.
//
#import <QuartzCore/QuartzCore.h>
#import "ModelStore.h"

#import "OverviewViewController.h"
#import "OverviewTableCellView.h"
#import "OverviewTableRowView.h"

#import "GeneralPreferencesViewController.h"
#import "NSButton+TextColor.h"

//BETA
#import "AppDelegate.h"

@implementation OverviewViewController
@synthesize managedObjectContext = _managedObjectContext;
@synthesize panelController = _panelController;
@synthesize aboutWindowController = _aboutWindowController;
@synthesize activitySortDescriptors;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:@"OverviewViewController" bundle:nibBundleOrNil];
    if (self) 
    {
        _managedObjectContext = [[ModelStore sharedStore] managedObjectContext];
        
        //set up Timer notifications
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(PomodoroTimerStarted:) name:EGG_START object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(PomodoroTimeCompleted:) name:EGG_COMPLETE object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(PomodoroStopped:) name:EGG_STOP object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(PomodoroRequested:) name:EGG_REQUESTED object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pomodoroPaused:) name:EGG_PAUSE object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pomodoroResume:) name:EGG_RESUME object:nil];
        
        //set up Activity notifications
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ActivityModifiedCompletion:) name:ACTIVITY_MODIFIED object:nil];
    
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    if(!firstRun)
    {
        //add hidden logo
        CGRect r = CGRectMake(85, -55, 151, 32);
        NSImageView *imv = [[NSImageView alloc] initWithFrame:NSRectFromCGRect(r)];
        imv.image = [NSImage imageNamed:@"hiddenLogo.png"];
        imv.alphaValue = 1;
        [listScrollView.contentView addSubview:imv];
        
        //Filter for removed activities, or ones that are completed but over a week old.
        NSDate *weekAgo = [NSDate dateWithTimeIntervalSinceNow:-4838400];
        arrayController.fetchPredicate = [NSPredicate predicateWithFormat:@"(removed == 0) OR (completed == 1 AND modified > %@ AND removed == 0)", weekAgo, nil];

        //set target and action of double click to this class
        [itemsTableView setTarget:self];
        [itemsTableView setDoubleAction:@selector(cellDoubleClicked:)];
        [itemsTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
        
        //center the text    
        NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];    
        pStyle.alignment = NSCenterTextAlignment;
        NSColor *txtColor = [NSColor whiteColor];
        NSFont *txtFont = [NSFont systemFontOfSize:12];
        NSShadow *shadow = [[NSShadow alloc] init];
        [shadow setShadowOffset:NSMakeSize(0.0,-1.0)];
        [shadow setShadowBlurRadius:1.0];
        [shadow setShadowColor:[NSColor colorWithDeviceWhite:0.0 alpha:0.7]];
        
        NSDictionary *txtDict = [NSDictionary dictionaryWithObjectsAndKeys:pStyle, NSParagraphStyleAttributeName, txtFont, NSFontAttributeName, txtColor,  NSForegroundColorAttributeName, shadow, NSShadowAttributeName, nil];
        
        startString = [[NSMutableAttributedString alloc] initWithString:@"Start" attributes:txtDict];
        stopString  = [[NSMutableAttributedString alloc] initWithString:@"Stop"  attributes:txtDict];
        resumeString = [[NSMutableAttributedString alloc] initWithString:@"Resume" attributes:txtDict];
        
        startButton.toolTip = @"Start a Pomodoro (⌘ Enter)";
        addTaskButton.toolTip = @"Add a new task (⌘ N)";
        
        [startButton setAttributedTitle:startString];
        
        currentClippedRow = -1;
        firstRun = YES;
    }
}

#pragma mark - PanelViewController methods

- (void)viewWillAppear
{
    [itemsTableView deselectAll:self];
}

- (void)viewDidAppear
{
    [itemsTableView reloadData];
    [itemsTableView becomeFirstResponder];
    
    EggTimer *currentTimer = [EggTimer currentTimer];
    if(currentTimer && currentTimer.status == TimerStatusRunning && currentTimer.type == TimerTypePomodoro)
    {
        Activity *currentActivity = [Activity currentActivity];
        if(!currentActivity)
            return;
        
        NSUInteger i = [arrayController.arrangedObjects indexOfObject:currentActivity];
        NSIndexSet *newlySelectedRow = [NSIndexSet indexSetWithIndex:i];
        [itemsTableView editColumn:0
                               row:0
                         withEvent:nil
                            select:YES];
        [itemsTableView selectRowIndexes:newlySelectedRow byExtendingSelection:YES];
        [itemsTableView scrollRowToVisible:i];
    }
}

- (void)viewDidDisappear;
{
    [itemsTableView reloadData];
}

#pragma mark - Data related methods

- (NSArray *)activitySortDescriptors
{
    return [NSArray arrayWithObjects:
            [NSSortDescriptor sortDescriptorWithKey:@"completed"
                                          ascending:YES],
            [NSSortDescriptor sortDescriptorWithKey:@"created" 
                                          ascending:NO],
            nil];
}

#pragma mark - TableView Delegate and Datasource methods

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    if(row >= [arrayController.arrangedObjects count])
        return 70;
    
    Activity *a = (Activity *)[arrayController.arrangedObjects objectAtIndex:row];
    CGFloat height = 70;
    if([a class] == [Activity class])
    {
        //completed ribbons do not have a pull out. this might change for interruptions
        BOOL selected = ([tableView selectedRow] == row && (![a.completed boolValue]));
        height = [OverviewTableCellView heightForTitle:a.name selected:selected];
    }
    return height;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row 
{
    OverviewTableCellView *result = [itemsTableView makeViewWithIdentifier:@"OverviewTableCellView" owner:self];
    [result.backgroundClip setHidden:YES];
    
    //set the appropriate selection
    NSTableRowView *rowView = [itemsTableView rowViewAtRow:row makeIfNecessary:NO];
    
//    NSLog(@"Number of Tasks: %ld", [arrayController.arrangedObjects count]);
    Activity *a = (Activity *)[arrayController.arrangedObjects objectAtIndex:row];
    result.textField.stringValue = a.name;
    result.selected = rowView.selected;

    return result;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    OverviewTableRowView *rowView = [[OverviewTableRowView alloc] init];
    return rowView;
}

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
    int prevRowIndex = (int)[aTableView selectedRow];
    int clippedIndex = prevRowIndex + 1;
    
    if(prevRowIndex >= 0 && clippedIndex < [arrayController.arrangedObjects count]) 
    {
        NSTableRowView *rowView = [itemsTableView rowViewAtRow:clippedIndex makeIfNecessary:NO];
        if(rowView)
        {
            OverviewTableCellView *dr = (OverviewTableCellView *)[rowView viewAtColumn:0];
            [dr.backgroundClip setHidden:YES];
        }
    }
    Activity *a = (Activity *)[arrayController.arrangedObjects objectAtIndex:rowIndex];
    if([a.completed boolValue])
        return YES;
    
    clippedIndex = (int)rowIndex + 1;
    if(clippedIndex < [arrayController.arrangedObjects count])
    {
        NSTableRowView *rowView = [itemsTableView rowViewAtRow:clippedIndex makeIfNecessary:NO];
        if(rowView)
        {
            OverviewTableCellView *dr = (OverviewTableCellView *)[rowView viewAtColumn:0];
            [dr.backgroundClip setHidden:NO];
            currentClippedRow = clippedIndex;
        }
    }

    return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    doubleClicked = NO;
    
    NSIndexSet *selectedIndexSet = [itemsTableView selectedRowIndexes];
    if([selectedIndexSet count] < 2)
    {
        NSIndexSet *allOfTheTea = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, itemsTableView.numberOfRows)];
        [itemsTableView noteHeightOfRowsWithIndexesChanged:allOfTheTea];
    }
    
    int sr = (int)[itemsTableView selectedRow];
    if(sr < 0)
    {
        if(currentClippedRow > -1 && currentClippedRow < [arrayController.arrangedObjects count])
        {
            NSTableRowView *rowView = [itemsTableView rowViewAtRow:currentClippedRow makeIfNecessary:NO];
            if(rowView)
            {
                OverviewTableCellView *dr = (OverviewTableCellView *)[rowView viewAtColumn:0];
                [dr.backgroundClip setHidden:YES];
                currentClippedRow = -1;
            }
        }
        return;   
    }
    
    Activity *a = (Activity *)[arrayController.arrangedObjects objectAtIndex:sr];
    if([a class] == [Activity class])
    {
        if([[startButton attributedTitle] isEqualToAttributedString:startString])
            [startButton setEnabled:![a.completed boolValue]];
    }
}

#pragma mark - NSButton IBActions

- (IBAction)debugSelected:(id)sender
{
    //used for debug purposes
}

- (IBAction)noteSelected:(id)sender;
{
    AppDelegate *appDelegate = (AppDelegate *)[NSApplication sharedApplication].delegate;
    [appDelegate toggleNoteKeyed:nil];
}

- (IBAction)cellDoubleClicked:(id)sender;
{
    OverviewTableCellView *cellView = [itemsTableView viewAtColumn:0 row:[itemsTableView selectedRow] makeIfNecessary:NO];
    
    if(cellView && [cellView class] == [OverviewTableCellView class])
    {
        [cellView.textField setEditable:YES];
        [itemsTableView editColumn:0 
                               row:[itemsTableView selectedRow]
                         withEvent:nil
                            select:YES];
    }
}

- (IBAction)addItem:(id)sender;
{
    arrayController.filterPredicate = nil;

    [itemsTableView reloadData];
    [itemsTableView deselectAll:self];
    Activity *newActivity = [Activity activity];
    newActivity.name = NSLocalizedString(@"new task", @"new task");
    newActivity.plannedCount = [NSNumber numberWithInt:1];
    [newActivity save];
    
    NSIndexSet *newlySelectedRow = [NSIndexSet indexSetWithIndex:0];
    [itemsTableView editColumn:0
                           row:0
                     withEvent:nil
                        select:YES];
    [itemsTableView selectRowIndexes:newlySelectedRow byExtendingSelection:YES];

}

- (IBAction)removeItem:(id)sender;
{
    
    NSInteger selectedIndex = [itemsTableView selectedRow];
    Activity *a = [arrayController.arrangedObjects objectAtIndex:selectedIndex];
    if([Activity currentActivity] == a && [startButton.attributedTitle isEqualToAttributedString:stopString])
        return;
    
    OverviewTableCellView *otcv = (OverviewTableCellView *)[itemsTableView viewAtColumn:0 row:selectedIndex makeIfNecessary:NO];
    if(otcv)
    {
        otcv.selected = NO;
    }
    
    a.removed = [NSNumber numberWithBool:YES];
    [a save];
    
//    NSIndexSet *selectedIndexes = [itemsTableView selectedRowIndexes];
//    
//    [selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
//        
//        Activity *a = [arrayController.arrangedObjects objectAtIndex:0];
//        if([Activity currentActivity] == a && [startButton.attributedTitle isEqualToAttributedString:stopString])
//            return;
//        
//        OverviewTableCellView *otcv = (OverviewTableCellView *)[itemsTableView viewAtColumn:0 row:0 makeIfNecessary:NO];
//        if(otcv)
//        {
//            otcv.selected = NO;
//        }
//        
//        a.removed = [NSNumber numberWithBool:YES];
//        [a save];
//        
//    }];
}

- (IBAction)pinPanel:(id)sender;
{
    self.panelController.pinned = !self.panelController.pinned;
}

- (IBAction)showOptionsMenu:(id)sender;
{
    NSRect frame = [(NSButton *)sender frame];
    NSPoint menuOrigin = [[(NSButton *)sender superview] convertPoint:NSMakePoint(frame.origin.x, frame.origin.y+frame.size.height-30) toView:nil];
    
    NSEvent *event =  [NSEvent mouseEventWithType:NSLeftMouseDown
                                         location:menuOrigin
                                    modifierFlags:NSLeftMouseDownMask // 0x100
                                        timestamp:0
                                     windowNumber:[[(NSButton *)sender window] windowNumber]
                                          context:[[(NSButton *)sender window] graphicsContext]
                                      eventNumber:0
                                       clickCount:1
                                         pressure:1];
    
    [NSMenu popUpContextMenu:optionsMenu withEvent:event forView:(NSButton *)sender];
}

- (IBAction)startANewPomodoro:(id)sender;
{
    EggTimer *currentTimer = [EggTimer currentTimer];

    NSInteger selectedIndex;
    switch([currentTimer status])
    {

        case TimerStatusPaused:
            [currentTimer resume];
            break;
            
        case TimerStatusRunning:
            [currentTimer stop];
            break;
         
        case TimerStatusStopped:
        default:
            //set the selected activity as the currentActivity
            selectedIndex = [itemsTableView selectedRow];
            if(selectedIndex < 0)
                return;
            
            Activity *a = [arrayController.arrangedObjects objectAtIndex:selectedIndex];
            
            EggTimer *pomo = [a crackAnEgg];
            [pomo startAfterDelay:EGG_REQUEST_DELAY];
            break;
    }
}

- (IBAction)increasePomodoroCountForSelectedRow:(id)sender
{
    [self modifyPomodoroCountForSelectedRow:1];
}

- (IBAction)decreasePomodoroCountForSelectedRow:(id)sender
{
    [self modifyPomodoroCountForSelectedRow:-1];
}

#pragma mark - NSMenu IBActions

- (IBAction)showHelpMenu:(id)sender;
{
    [[NSApplication sharedApplication] showHelp:nil];
//    NSURL *url = [NSURL URLWithString:@"http://www.monoclesociety.com/r/eggscellent/support"];
//    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)showAboutMenu:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    [self.aboutWindowController showWindow:self];
}

- (IBAction)openPreferences:(id)sender;
{
    [self.panelController.delegate performSelector:@selector(openPreferences)];
}

- (IBAction)quitApplication:(id)sender;
{
    [[NSApplication sharedApplication] terminate:self];
}

- (IBAction)checkForUpdates:(id)sender;
{

}

- (IBAction)closePanelWindow:(id)sender;
{
    [self.panelController closePanel];
}

#pragma mark - Notifications

- (void)PomodoroRequested:(NSNotification *)note
{
    [startButton setEnabled:NO];
    [self changeButtonToStart:NO];
}

- (void)PomodoroTimerStarted:(NSNotification *)note
{
    [startButton setEnabled:YES];
    EggTimer *pomo = (EggTimer *)[note object];
    if(pomo.type == TimerTypePomodoro)
    {
        [self changeButtonToStart:NO];
    }
}

- (void)PomodoroTimeCompleted:(NSNotification *)note
{
    EggTimer *pomo = (EggTimer *)[note object];
    if(pomo.type == TimerTypePomodoro)
    {    
        [self changeButtonToStart:YES];
        //TODO: change title of start button here
    }
}

- (void)PomodoroStopped:(NSNotification *)note
{
    EggTimer *pomo = (EggTimer *)[note object];
    if(pomo.type == TimerTypePomodoro)
    {    
        [self changeButtonToStart:YES];
        //TODO: change title of start button here
    }
}

- (void)pomodoroPaused:(NSNotificationCenter *)note
{
    [startButton setAttributedTitle:resumeString];
    startButton.image = [NSImage imageNamed:@"button-resume"];
    startButton.alternateImage = [NSImage imageNamed:@"button-resume-down"];
    startButton.toolTip = NSLocalizedString(@"Resume Pomodoro (⌘ Enter)", nil);
}

- (void)pomodoroResume:(NSNotificationCenter *)note
{
    [self changeButtonToStart:NO];
}

- (void)ActivityModifiedCompletion:(NSNotification *)note
{
    if([itemsTableView selectedRow] < 0)
        return;
    
    Activity *a = (Activity *)[note object];
    Activity *b = (Activity *)[arrayController.arrangedObjects objectAtIndex:[itemsTableView selectedRow]];
    if(a == b && ([a.completed boolValue] != [b.completed boolValue]))
    {
        if([a.completed boolValue] && [[startButton attributedTitle] isEqualToAttributedString:startString])
            [startButton setEnabled:NO];
        else
            [startButton setEnabled:YES];
    }
}

#pragma mark - custom methods

- (void)setRowclippedAtIndex:(int)index;
{
    
}

- (void)changeButtonToStart:(BOOL)start;
{
    if(start)
    {
        [startButton setAttributedTitle:startString];
        startButton.image = [NSImage imageNamed:@"button-start"];
        startButton.alternateImage = [NSImage imageNamed:@"button-start-down"];
        startButton.toolTip = NSLocalizedString(@"Start a Pomodoro (⌘ Enter)", nil);
    }
    else
    {
        [startButton setAttributedTitle:stopString];
        startButton.image = [NSImage imageNamed:@"button-stop"];
        startButton.alternateImage = [NSImage imageNamed:@"button-stop-down"];
        startButton.toolTip = NSLocalizedString(@"Stop a Pomodoro (⌘ Enter)", nil);
    }
}

- (void)modifyPomodoroCountForSelectedRow:(int)modValue;
{
    int selectedIndex = (int)[itemsTableView selectedRow];
    if(selectedIndex < 0) 
        return;

    OverviewTableCellView *otcv = (OverviewTableCellView *)[itemsTableView viewAtColumn:0 row:selectedIndex makeIfNecessary:NO];
    if(otcv)
    {
        [otcv modifyPomodoroCount:modValue];
    } 
}

#pragma mark - Property based methods

- (AboutWindowController *)aboutWindowController 
{
	if (_aboutWindowController) return _aboutWindowController;
	_aboutWindowController = [[AboutWindowController alloc] init];
	return _aboutWindowController;
}

@end