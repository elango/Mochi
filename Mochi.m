//
//  Mochi.m
//
//  Created by Douglas Pedley on 5/27/10.
//

#import "Mochi.h"

#define MOCHI_DOCUMENTS_DIRECTORY [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject]

static Mochi *sharedMochi;
static NSDictionary *mochiClasses;

@implementation Mochi

@synthesize managedObjectModel, managedObjectContext, persistentStoreCoordinator, dataFile, dataModel, disableUndoManager;

#pragma mark Initial settings
+(void)settingsFromDictionary:(NSDictionary *)settingsDictionary
{
	@synchronized(sharedMochi) 
	{
		sharedMochi = [[Mochi alloc] initWithDictionary:settingsDictionary];
		NSDictionary *classMappings = [settingsDictionary objectForKey:@"classMappings"];
		
		NSArray *allKeys = [classMappings allKeys];
		NSMutableDictionary *buildMochi = [NSMutableDictionary dictionaryWithCapacity:[allKeys count]];
		for (NSString *key in allKeys)
		{
			Mochi *classMochi = [[Mochi alloc] initWithDictionary:[classMappings objectForKey:key]];
			[buildMochi setObject:classMochi forKey:key];
		}
		mochiClasses = [[NSDictionary alloc] initWithDictionary:buildMochi]; 
	}
}

-(id)initWithDictionary:(NSDictionary *)settings
{
	if ([super init])
	{
		NSString *database  = [[settings valueForKey:@"database"] stringByAppendingString:@".sqlite"];
		NSString *model = [settings valueForKey:@"model"];
		NSNumber *bDisableUndoManager = [settings valueForKey:@"disableUndoManager"];
		
		self.dataFile = database;
		self.dataModel = model;
		
		if (bDisableUndoManager!=nil) 
		{
			self.disableUndoManager = [bDisableUndoManager boolValue];
		}
		else 
		{
			self.disableUndoManager = NO;
		}		
	}
	
	return self;
}

-(void)defaultDatabaseFromBundle
{
	[self defaultDatabaseFromBundle:NO];
}

-(void)defaultDatabaseFromBundle:(BOOL)overwriteIfExists
{
    NSString *toDB = [MOCHI_DOCUMENTS_DIRECTORY stringByAppendingPathComponent:self.dataFile];
    NSString *fromDB = [[[NSBundle bundleForClass:[self class]] resourcePath] stringByAppendingPathComponent:self.dataFile];
	
	// Only copy the default database if it doesn't already exist
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if (!overwriteIfExists && [fileManager fileExistsAtPath:toDB]) 
	{
		return;
	}
	
	
    NSError *error;
    if (![fileManager copyItemAtPath:fromDB toPath:toDB error:&error]) 
	{
        NSLog(@"Couldn't copy database from application bundle \n[%@].", [error localizedDescription]);
    }
}

#pragma mark NSManagedObjectContext, NSPersistentStoreCoordinator, NSManagedObjectModel property accessors  

-(NSManagedObjectContext *)managedObjectContext 
{
    if (managedObjectContext!=nil) 
	{
        return managedObjectContext;
    }
	
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
	
	if (coordinator!=nil) 
	{
        managedObjectContext = [[NSManagedObjectContext alloc] init];
        [managedObjectContext setPersistentStoreCoordinator: coordinator];
		if (disableUndoManager) { [managedObjectContext setUndoManager:nil]; }
    }
	
    return managedObjectContext;
}

-(NSManagedObjectModel*)managedObjectModel 
{
	if (managedObjectModel) 
	{
		return managedObjectModel;
	}
	
	NSURL *momFile = [NSURL fileURLWithPath:[[NSBundle bundleForClass:[Mochi class]] pathForResource:self.dataModel ofType:@"mom"]];
	managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:momFile];
	return managedObjectModel;
}

-(NSPersistentStoreCoordinator *)persistentStoreCoordinator 
{
    if (persistentStoreCoordinator != nil) 
	{
        return persistentStoreCoordinator;
    }
	
    NSURL *pscUrl = [NSURL fileURLWithPath:[MOCHI_DOCUMENTS_DIRECTORY stringByAppendingPathComponent: self.dataFile]];
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
	
	NSError *error;
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:pscUrl options:nil error:&error]) 
	{
		NSLog(@"Error adding persistant store coordinator %@", [error localizedDescription]);
    }
	
    return persistentStoreCoordinator;
}

-(void)dealloc 
{
	[managedObjectModel release];
	[managedObjectContext release];
	[persistentStoreCoordinator release];
	
    [super dealloc];
}

#pragma mark Singleton Helpers

+(id)sharedMochi 
{ 
	return sharedMochi;
}

+(id)mochiForClass:(Class)mochiClass
{
	@synchronized(self) 
	{ 
		if (sharedMochi == nil) 
		{
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			[self settingsFromDictionary:[defaults dictionaryRepresentation]];
		}
	}

	id ret = [mochiClasses objectForKey:[mochiClass description]];
	if (ret==NULL) 
	{
		return sharedMochi;
	}
	return ret;
}

-(id)copyWithZone:(NSZone *)zone 
{ 
	return self; 
} 

-(id)retain 
{ 
	return self; 
} 

-(NSUInteger)retainCount 
{ 
	return NSUIntegerMax; 
} 

-(void)release 
{ 
} 

-(id)autorelease 
{ 
	return self; 
}

@end



/*
 
 These are the Mochi Managed Object Category Additions
 they are helpers to do the common database load, save, search type of functionality
 
 */

static NSMutableDictionary *mochiClassIDs = nil;
static NSError *mochiLastError;

@interface NSManagedObject (MochiPrivate)

+(NSEntityDescription *)entityDescription;
+(NSString *)mochiIndexName;
+(void)setMochiIndexName:(NSString *)value;

@end


@implementation NSManagedObject (Mochi)

+(NSEntityDescription *)mochiEntityDescription
{
	return [NSEntityDescription entityForName:[self description] inManagedObjectContext:[[Mochi mochiForClass:[self class]] managedObjectContext]];
}

+(NSString *)mochiIndexName
{
	return [mochiClassIDs valueForKey:[self description]];
}

+(void)setMochiIndexName:(NSString *)value
{
	if (mochiClassIDs==nil) 
	{
		mochiClassIDs = [[NSMutableDictionary alloc] initWithObjectsAndKeys:[value retain], [self description], nil];
	}
	else 
	{
		[mochiClassIDs setValue:[value retain] forKey:[self description]];
	}
}

+(id)addNew 
{
	return [NSEntityDescription insertNewObjectForEntityForName:[self description] inManagedObjectContext:[[Mochi mochiForClass:[self class]] managedObjectContext]];
}

+(id)addNewWithIndex:(NSNumber *)ID 
{
	id newObject = [self addNew];
	NSString *fieldNameID = [self mochiIndexName];
	if (fieldNameID!=nil)
	{
		[(NSManagedObject *)newObject setValue:ID forKey:fieldNameID];
	}
	return newObject;
}

+(id)withMatchingIndex:(NSValue *)indexValue
{
	NSString *ndxName = [self mochiIndexName];
	if (ndxName!=nil)
	{
		return [self withAttributeNamed:ndxName matchingValue:indexValue];
	}
	return nil;
}

+(int)count
{
	NSFetchRequest *req = [[[NSFetchRequest alloc] init] autorelease];
	req.entity = [self mochiEntityDescription];
	return [[[Mochi mochiForClass:[self class]] managedObjectContext] countForFetchRequest:req error:&mochiLastError];
}

+(NSArray *)allObjects
{
	NSFetchRequest *req = [[[NSFetchRequest alloc] init] autorelease];
	req.entity = [self mochiEntityDescription];
	return [[[Mochi mochiForClass:[self class]] managedObjectContext] executeFetchRequest:req error:&mochiLastError];
}

+(id)arrayWithAttributeNamed:(NSString *)field matchingValue:(id)value
{
	NSFetchRequest *req = [[[NSFetchRequest alloc] init] autorelease];
	req.entity = [self mochiEntityDescription];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"%@ = $V", field, nil]];
	predicate = [predicate predicateWithSubstitutionVariables:[NSDictionary dictionaryWithObject:value forKey:@"V"]];
	[req setPredicate:predicate];
	NSArray *fetchResponse = [[[Mochi mochiForClass:[self class]] managedObjectContext] executeFetchRequest:req error:&mochiLastError];
	if ((fetchResponse != nil) || ([fetchResponse count]>0))
	{
		id retArray = [fetchResponse mutableCopy];
		return retArray;
	}
	return nil;
}

+(id)withAttributeNamed:(NSString *)field matchingValue:(id)value
{
	NSArray *all = [self arrayWithAttributeNamed:field matchingValue:value];
	if ((all==nil) || ([all count]==0)) 
	{
		return nil;
	}
	return [all objectAtIndex:0];
}

+(void)save 
{
	[[Mochi mochiForClass:[self class]] save];
}

-(void)remove
{
	Mochi *mochi = [Mochi mochiForClass:[self class]];
	[mochi.managedObjectContext deleteObject:self];
	[mochi.managedObjectContext save:&mochiLastError];
}

+(void)removeAll
{
	Mochi *mochi = [Mochi mochiForClass:[self class]];
	NSArray *all = [self allObjects];
	for (id currentObject in all) 
	{
		[mochi.managedObjectContext deleteObject:currentObject];
	}
	[mochi.managedObjectContext save:&mochiLastError]; 
}

@end
