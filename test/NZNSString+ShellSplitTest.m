#import <SenTestingKit/SenTestingKit.h>

@interface NZNSStringShellSplitTest : SenTestCase {}

@end

// This is here to avoid warnings with the compiler
@interface NSString (NZShellSplit)
- (NSArray *)componentsSeparatedByShell;
@end

@implementation NZNSStringShellSplitTest

- (void)testOneArgumentString {
  NSString *cmd = @"abc";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)1,
                 @"A command with one argument should have only one argument.");
  STAssertTrue([@"abc" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
}

- (void)testTwoArgumentsSeparatedByOneSpace {
  NSString *cmd = @"abc def";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)2,
                 @"A command with two argument should have two arguments.");
  STAssertTrue([@"abc" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
  STAssertTrue([@"def" isEqualToString:[args objectAtIndex:1]],
               @"The argument #1 should be 'def'.");
}

- (void)testTwoArgumentsSeparatedByMoreSpaces {
  NSString *cmd = @"abc     def";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)2,
                 @"A command with two argument should have two arguments.");
  STAssertTrue([@"abc" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
  STAssertTrue([@"def" isEqualToString:[args objectAtIndex:1]],
               @"The argument #1 should be 'def'.");
}

- (void)testThreeArgumentsSeparatedBySpaces {
  NSString *cmd = @"abc    def ghi";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)3,
                 @"A command with three argument should have three arguments.");
  STAssertTrue([@"abc" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
  STAssertTrue([@"def" isEqualToString:[args objectAtIndex:1]],
               @"The argument #1 should be 'def'.");
  STAssertTrue([@"ghi" isEqualToString:[args objectAtIndex:2]],
               @"The argument #2 should be 'ghi'.");
}

- (void)testOneArgumentWithDoubleQuotes {
  NSString *cmd = @"\"abc\"";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)1,
                 @"A command with one quoted argument should have one argument.");
  STAssertTrue([@"abc" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
}

- (void)testOneArgumentWithSingleQuotes {
  NSString *cmd = @"'abc'";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)1,
                 @"A command with one quoted argument should have one argument.");
  STAssertTrue([@"abc" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
}

- (void)testOneQuotedArgumentWithEscapedQuotes {
  NSString *cmd = @"'ab\\'c'";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)1,
                 @"A command with one quoted argument should have one argument.");
  STAssertTrue([@"ab'c" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
}

- (void)testOneQuotedArgumentWithSpaces {
  NSString *cmd = @"'abc def ghi'";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)1,
                 @"A command with one quoted argument should have one argument.");
  STAssertTrue([@"abc def ghi" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc def ghi'.");
}

- (void)testOneQuotedArgumentWithOtherUnescapedQuotes {
  NSString *cmd = @"'abc\"ghi'";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)1,
                 @"A command with one quoted argument should have one argument.");
  STAssertTrue([@"abc\"ghi" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc\"ghi'.");
}

- (void)testBackSlashAtEnd {
  NSString *cmd = @"abc ghi\\";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)2,
                 @"A command with two arguments should have two arguments.");
  STAssertTrue([@"abc" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
  STAssertTrue([@"ghi\\" isEqualToString:[args objectAtIndex:1]],
               @"The argument #1 should be 'ghi\\'.");
}

- (void)testEscapedQuotes {
  NSString *cmd = @"\\\" \\'";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)2,
                 @"A command with two arguments should have two arguments.");
  STAssertTrue([@"\"" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be '\"'.");
  STAssertTrue([@"'" isEqualToString:[args objectAtIndex:1]],
               @"The argument #1 should be '''.");
}

- (void)testUnmatchedDoubleQuotes {
  NSString *cmd = @"abc \"def";
  STAssertThrowsSpecificNamed([cmd componentsSeparatedByShell],
                              NSException, NSInvalidArgumentException,
                              @"A command with unmatched quotes should throw "
                              @"a unmatched quotes exception.");
}

- (void)testUnmatchedSingleQuotes {
  NSString *cmd = @"abc 'def";
  STAssertThrowsSpecificNamed([cmd componentsSeparatedByShell],
                              NSException, NSInvalidArgumentException,
                              @"A command with unmatched quotes should throw "
                              @"a unmatched quotes exception.");
}

- (void)testMixedQuotedAndUnquoted {
  NSString *cmd = @"\"abc\" -d \"efg\"";
  NSArray *args = [cmd componentsSeparatedByShell];
  
  STAssertEquals([args count], (NSUInteger)3,
                 @"A command with two arguments should have two arguments.");
  STAssertTrue([@"abc" isEqualToString:[args objectAtIndex:0]],
               @"The argument #0 should be 'abc'.");
  STAssertTrue([@"-d" isEqualToString:[args objectAtIndex:1]],
               @"The argument #1 should be '-d'.");
  STAssertTrue([@"efg" isEqualToString:[args objectAtIndex:2]],
               @"The argument #2 should be 'efg'.");
}

@end