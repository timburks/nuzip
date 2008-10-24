/*!
@file NuZip.m
@discussion Objective-C wrapper for Gilles Vollant's Minizip library.
@copyright Copyright (c) 2008 Neon Design Technology, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#import "NuZip.h"

static int opt_quiet = 0;
int nuzip_printf(const char *format, ...)
{
    if (!opt_quiet) {
        va_list ap;
        va_start(ap, format);
        vprintf(format, ap);
        va_end(ap);
    }
}

int unzip_main(int argc, char *argv[]);

int zip_main(int argc, char *argv[]);

@implementation NuZip

+ (int) unzip:(NSString *) command
{
    NSArray *args = [command componentsSeparatedByString:@" "];
    int argc = [args count];
    char **argv = (char **) malloc ([args count] * sizeof (char *));
    int i;
    for (i = 0; i < argc; i++) {
        argv[i] = strdup([[args objectAtIndex:i] cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    int result = unzip_main(argc, argv);
    for (i = 0; i < argc; i++) {
        free(argv[i]);
    }
    free(argv);
    return result;
}

+ (int) zip:(NSString *) command
{
    NSArray *args = [command componentsSeparatedByString:@" "];
    int argc = [args count];
    char **argv = (char **) malloc ([args count] * sizeof (char *));
    int i;
    for (i = 0; i < argc; i++) {
        argv[i] = strdup([[args objectAtIndex:i] cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    int result = zip_main(argc, argv);
    for (i = 0; i < argc; i++) {
        free(argv[i]);
    }
    free(argv);
    return result;
}

@end

/*
   miniunz.c
   Version 1.01e, February 12th, 2005

   Copyright (C) 1998-2005 Gilles Vollant
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
# include <sys/stat.h>

# include <unistd.h>
# include <utime.h>

#include "unzip.h"
#include "zip.h"

#define CASESENSITIVITY (0)
#define MAXFILENAME (256)
#define WRITEBUFFERSIZE (16384)

/*
  mini unzip, demo of unzip package

  usage :
  Usage : miniunz [-exvlo] file.zip [file_to_extract] [-d extractdir]

  list the file in the zipfile, and print the content of FILE_ID.ZIP or README.TXT
    if it exists
*/

/* change_file_date : change the date/time of a file
    filename : the filename of the file where date/time must be modified
    dosdate : the new date at the MSDos format (4 bytes)
    tmu_date : the SAME new date at the tm_unz format */
void change_file_date(const char *filename, uLong dosdate, tm_unz tmu_date)
{
    struct utimbuf ut;
    struct tm newdate;
    newdate.tm_sec = tmu_date.tm_sec;
    newdate.tm_min=tmu_date.tm_min;
    newdate.tm_hour=tmu_date.tm_hour;
    newdate.tm_mday=tmu_date.tm_mday;
    newdate.tm_mon=tmu_date.tm_mon;
    if (tmu_date.tm_year > 1900)
        newdate.tm_year=tmu_date.tm_year - 1900;
    else
        newdate.tm_year=tmu_date.tm_year ;
    newdate.tm_isdst=-1;

    ut.actime=ut.modtime=mktime(&newdate);
    utime(filename,&ut);
}

/* mymkdir and change_file_date are not 100 % portable
   As I don't know well Unix, I wait feedback for the unix portion */

int mymkdir(const char *dirname)
{
    int ret=0;
    ret = mkdir (dirname,0775);
    return ret;
}

int makedir (char *newdir)
{
    char *buffer ;
    char *p;
    int  len = (int)strlen(newdir);

    if (len <= 0)
        return 0;

    buffer = (char*)malloc(len+1);
    strcpy(buffer,newdir);

    if (buffer[len-1] == '/') {
        buffer[len-1] = '\0';
    }
    if (mymkdir(buffer) == 0) {
        free(buffer);
        return 1;
    }

    p = buffer+1;
    while (1) {
        char hold;

        while(*p && *p != '\\' && *p != '/')
            p++;
        hold = *p;
        *p = 0;
        if ((mymkdir(buffer) == -1) && (errno == ENOENT)) {
            nuzip_printf("couldn't create directory %s\n",buffer);
            free(buffer);
            return 0;
        }
        if (hold == 0)
            break;
        *p++ = hold;
    }
    free(buffer);
    return 1;
}

void do_unzip_banner()
{
    nuzip_printf("MiniUnz 1.01b, demo of zLib + Unz package written by Gilles Vollant\n");
    nuzip_printf("more info at http://www.winimage.com/zLibDll/unzip.html\n\n");
}

void do_unzip_help()
{
    nuzip_printf("Usage : miniunz [-e] [-x] [-v] [-l] [-o] [-p password] file.zip [file_to_extr.] [-d extractdir]\n\n" \
        "  -e  Extract without pathname (junk paths)\n" \
        "  -x  Extract with pathname\n" \
        "  -v  list files\n" \
        "  -l  list files\n" \
        "  -d  directory to extract into\n" \
        "  -o  overwrite files without prompting\n" \
        "  -p  extract crypted file using password\n\n");
}

int do_list(unzFile uf)
{
    uLong i;
    unz_global_info gi;
    int err;

    err = unzGetGlobalInfo (uf,&gi);
    if (err!=UNZ_OK)
        nuzip_printf("error %d with zipfile in unzGetGlobalInfo \n",err);
    nuzip_printf(" Length  Method   Size  Ratio   Date    Time   CRC-32     Name\n");
    nuzip_printf(" ------  ------   ----  -----   ----    ----   ------     ----\n");
    for (i=0;i<gi.number_entry;i++) {
        char filename_inzip[256];
        unz_file_info file_info;
        uLong ratio=0;
        const char *string_method;
        char charCrypt=' ';
        err = unzGetCurrentFileInfo(uf,&file_info,filename_inzip,sizeof(filename_inzip),NULL,0,NULL,0);
        if (err!=UNZ_OK) {
            nuzip_printf("error %d with zipfile in unzGetCurrentFileInfo\n",err);
            break;
        }
        if (file_info.uncompressed_size>0)
            ratio = (file_info.compressed_size*100)/file_info.uncompressed_size;

        /* display a '*' if the file is crypted */
        if ((file_info.flag & 1) != 0)
            charCrypt='*';

        if (file_info.compression_method==0)
            string_method="Stored";
        else
        if (file_info.compression_method==Z_DEFLATED) {
            uInt iLevel=(uInt)((file_info.flag & 0x6)/2);
            if (iLevel==0)
                string_method="Defl:N";
            else if (iLevel==1)
                string_method="Defl:X";
            else if ((iLevel==2) || (iLevel==3))
                string_method="Defl:F";           /* 2:fast , 3 : extra fast*/
        }
        else
            string_method="Unkn. ";

        nuzip_printf("%7lu  %6s%c%7lu %3lu%%  %2.2lu-%2.2lu-%2.2lu  %2.2lu:%2.2lu  %8.8lx   %s\n",
            file_info.uncompressed_size,string_method,
            charCrypt,
            file_info.compressed_size,
            ratio,
            (uLong)file_info.tmu_date.tm_mon + 1,
            (uLong)file_info.tmu_date.tm_mday,
            (uLong)file_info.tmu_date.tm_year % 100,
            (uLong)file_info.tmu_date.tm_hour,(uLong)file_info.tmu_date.tm_min,
            (uLong)file_info.crc,filename_inzip);
        if ((i+1)<gi.number_entry) {
            err = unzGoToNextFile(uf);
            if (err!=UNZ_OK) {
                nuzip_printf("error %d with zipfile in unzGoToNextFile\n",err);
                break;
            }
        }
    }

    return 0;
}

int do_extract_currentfile(unzFile uf, const int *popt_extract_without_path, int *popt_overwrite, const char *password)
{
    char filename_inzip[256];
    char* filename_withoutpath;
    char* p;
    int err=UNZ_OK;
    FILE *fout=NULL;
    void* buf;
    uInt size_buf;

    unz_file_info file_info;
    uLong ratio=0;
    err = unzGetCurrentFileInfo(uf,&file_info,filename_inzip,sizeof(filename_inzip),NULL,0,NULL,0);

    if (err!=UNZ_OK) {
        nuzip_printf("error %d with zipfile in unzGetCurrentFileInfo\n",err);
        return err;
    }

    size_buf = WRITEBUFFERSIZE;
    buf = (void*)malloc(size_buf);
    if (buf==NULL) {
        nuzip_printf("Error allocating memory\n");
        return UNZ_INTERNALERROR;
    }

    p = filename_withoutpath = filename_inzip;
    while ((*p) != '\0') {
        if (((*p)=='/') || ((*p)=='\\'))
            filename_withoutpath = p+1;
        p++;
    }

    if ((*filename_withoutpath)=='\0') {
        if ((*popt_extract_without_path)==0) {
            nuzip_printf("creating directory: %s\n",filename_inzip);
            mymkdir(filename_inzip);
        }
    }
    else {
        char* write_filename;
        int skip=0;

        if ((*popt_extract_without_path)==0)
            write_filename = filename_inzip;
        else
            write_filename = filename_withoutpath;

        err = unzOpenCurrentFilePassword(uf,password);
        if (err!=UNZ_OK) {
            nuzip_printf("error %d with zipfile in unzOpenCurrentFilePassword\n",err);
        }

        if (((*popt_overwrite)==0) && (err==UNZ_OK)) {
            char rep=0;
            FILE* ftestexist;
            ftestexist = fopen(write_filename,"rb");
            if (ftestexist!=NULL) {
                fclose(ftestexist);
                do {
                    char answer[128];
                    int ret;

                    nuzip_printf("The file %s exists. Overwrite ? [y]es, [n]o, [A]ll: ",write_filename);
                    ret = scanf("%1s",answer);
                    if (ret != 1) {
                        return(EXIT_FAILURE);
                    }
                    rep = answer[0] ;
                    if ((rep>='a') && (rep<='z'))
                        rep -= 0x20;
                }
                while ((rep!='Y') && (rep!='N') && (rep!='A'));
            }

            if (rep == 'N')
                skip = 1;

            if (rep == 'A')
                *popt_overwrite=1;
        }

        if ((skip==0) && (err==UNZ_OK)) {
            fout=fopen(write_filename,"wb");

            /* some zipfile don't contain directory alone before file */
            if ((fout==NULL) && ((*popt_extract_without_path)==0) &&
            (filename_withoutpath!=(char*)filename_inzip)) {
                char c=*(filename_withoutpath-1);
                *(filename_withoutpath-1)='\0';
                makedir(write_filename);
                *(filename_withoutpath-1)=c;
                fout=fopen(write_filename,"wb");
            }

            if (fout==NULL) {
                nuzip_printf("error opening %s\n",write_filename);
            }
        }

        if (fout!=NULL) {
            nuzip_printf(" extracting: %s\n",write_filename);

            do {
                err = unzReadCurrentFile(uf,buf,size_buf);
                if (err<0) {
                    nuzip_printf("error %d with zipfile in unzReadCurrentFile\n",err);
                    break;
                }
                if (err>0)
                if (fwrite(buf,err,1,fout)!=1) {
                    nuzip_printf("error in writing extracted file\n");
                    err=UNZ_ERRNO;
                    break;
                }
            }
            while (err>0);
            if (fout)
                fclose(fout);

            if (err==0)
                change_file_date(write_filename,file_info.dosDate,
                    file_info.tmu_date);
        }

        if (err==UNZ_OK) {
            err = unzCloseCurrentFile (uf);
            if (err!=UNZ_OK) {
                nuzip_printf("error %d with zipfile in unzCloseCurrentFile\n",err);
            }
        }
        else
            unzCloseCurrentFile(uf);              /* don't lose the error */
    }

    free(buf);
    return err;
}

int do_extract(unzFile uf, int opt_extract_without_path, int opt_overwrite, const char *password)
{
    uLong i;
    unz_global_info gi;
    int err;
    FILE* fout=NULL;

    err = unzGetGlobalInfo (uf,&gi);
    if (err!=UNZ_OK)
        nuzip_printf("error %d with zipfile in unzGetGlobalInfo \n",err);

    for (i=0;i<gi.number_entry;i++) {
        if (do_extract_currentfile(uf,&opt_extract_without_path,
            &opt_overwrite,
            password) != UNZ_OK)
            break;

        if ((i+1)<gi.number_entry) {
            err = unzGoToNextFile(uf);
            if (err!=UNZ_OK) {
                nuzip_printf("error %d with zipfile in unzGoToNextFile\n",err);
                break;
            }
        }
    }

    return 0;
}

int do_extract_onefile(unzFile uf, const char *filename, int opt_extract_without_path, int opt_overwrite, const char *password)
{
    int err = UNZ_OK;
    if (unzLocateFile(uf,filename,CASESENSITIVITY)!=UNZ_OK) {
        nuzip_printf("file %s not found in the zipfile\n",filename);
        return 2;
    }

    if (do_extract_currentfile(uf,&opt_extract_without_path,
        &opt_overwrite,
        password) == UNZ_OK)
        return 0;
    else
        return 1;
}

int unzip_main(int argc, char *argv[])
{
    const char *zipfilename=NULL;
    const char *filename_to_extract=NULL;
    const char *password=NULL;
    char filename_try[MAXFILENAME+16] = "";
    int i;
    int opt_do_list=0;
    int opt_do_extract=1;
    int opt_do_extract_withoutpath=0;
    int opt_overwrite=0;
    int opt_extractdir=0;
    const char *dirname=NULL;
    unzFile uf=NULL;
    opt_quiet = 0;

    if (argc==0) {
        do_unzip_help();
        return 0;
    }
    else {
        for (i=0;i<argc;i++) {
            if ((*argv[i])=='-') {
                const char *p=argv[i]+1;

                while ((*p)!='\0') {
                    char c=*(p++);;
                    if ((c=='q') || (c=='Q'))
                        opt_quiet = 1;
                    if ((c=='l') || (c=='L'))
                        opt_do_list = 1;
                    if ((c=='v') || (c=='V'))
                        opt_do_list = 1;
                    if ((c=='x') || (c=='X'))
                        opt_do_extract = 1;
                    if ((c=='e') || (c=='E'))
                        opt_do_extract = opt_do_extract_withoutpath = 1;
                    if ((c=='o') || (c=='O'))
                        opt_overwrite=1;
                    if ((c=='d') || (c=='D')) {
                        opt_extractdir=1;
                        dirname=argv[i+1];
                    }

                    if (((c=='p') || (c=='P')) && (i+1<argc)) {
                        password=argv[i+1];
                        i++;
                    }
                }
            }
            else {
                if (zipfilename == NULL)
                    zipfilename = argv[i];
                else if ((filename_to_extract==NULL) && (!opt_extractdir))
                    filename_to_extract = argv[i] ;
            }
        }
    }

    if (zipfilename!=NULL) {
        strncpy(filename_try, zipfilename,MAXFILENAME-1);
        /* strncpy doesnt append the trailing NULL, of the string is too long. */
        filename_try[ MAXFILENAME ] = '\0';
        uf = unzOpen(zipfilename);
        if (uf==NULL) {
            strcat(filename_try,".zip");

            uf = unzOpen(filename_try);
        }
    }

    if (uf == NULL) {
        nuzip_printf("Cannot open %s or %s.zip\n",zipfilename,zipfilename);
        return 1;
    }
    nuzip_printf("%s opened\n",filename_try);

    if (opt_do_list==1)
        return do_list(uf);
    else if (opt_do_extract==1) {
        char originaldirname[1024];               // watch out!
        if (opt_extractdir)
            getcwd(originaldirname, 1024);
        if (opt_extractdir && chdir(dirname)) {
            nuzip_printf("Error changing into %s, aborting\n", dirname);
            return(-1);
        }
        int result;
        if (filename_to_extract == NULL)
            result = do_extract(uf, opt_do_extract_withoutpath, opt_overwrite,password);
        else
            result = do_extract_onefile(uf, filename_to_extract, opt_do_extract_withoutpath,opt_overwrite,password);
        if (opt_extractdir) {
            chdir(originaldirname);
        }
        return result;

    }
    unzCloseCurrentFile(uf);

    return 0;
}

/*
   minizip.c
   Version 1.01e, February 12th, 2005

   Copyright (C) 1998-2005 Gilles Vollant
*/

uLong filetime(char *f, tm_zip *tmzip, uLong *dt)
{
    int ret=0;
    struct stat s;                                /* results of stat() */
    struct tm* filedate;
    time_t tm_t=0;

    if (strcmp(f,"-")!=0) {
        char name[MAXFILENAME+1];
        int len = strlen(f);
        if (len > MAXFILENAME)
            len = MAXFILENAME;

        strncpy(name, f,MAXFILENAME-1);
        /* strncpy doesnt append the trailing NULL, of the string is too long. */
        name[ MAXFILENAME ] = '\0';

        if (name[len - 1] == '/')
            name[len - 1] = '\0';
        /* not all systems allow stat'ing a file with / appended */
        if (stat(name,&s)==0) {
            tm_t = s.st_mtime;
            ret = 1;
        }
    }
    filedate = localtime(&tm_t);

    tmzip->tm_sec  = filedate->tm_sec;
    tmzip->tm_min  = filedate->tm_min;
    tmzip->tm_hour = filedate->tm_hour;
    tmzip->tm_mday = filedate->tm_mday;
    tmzip->tm_mon  = filedate->tm_mon ;
    tmzip->tm_year = filedate->tm_year;

    return ret;
}

int check_exist_file(const char *filename)
{
    FILE* ftestexist;
    int ret = 1;
    ftestexist = fopen(filename,"rb");
    if (ftestexist==NULL)
        ret = 0;
    else
        fclose(ftestexist);
    return ret;
}

void do_zip_help()
{
    nuzip_printf("Usage : minizip [-o] [-a] [-0 to -9] [-p password] file.zip [files_to_add]\n\n" \
        "  -o  Overwrite existing file.zip\n" \
        "  -a  Append to existing file.zip\n" \
        "  -0  Store only\n" \
        "  -1  Compress faster\n" \
        "  -9  Compress better\n\n");
}

/* calculate the CRC32 of a file,
   because to encrypt a file, we need known the CRC32 of the file before */
int getFileCrc(const char* filenameinzip,void*buf,unsigned long size_buf,unsigned long* result_crc)
{
    unsigned long calculate_crc=0;
    int err=ZIP_OK;
    FILE * fin = fopen(filenameinzip,"rb");
    unsigned long size_read = 0;
    unsigned long total_read = 0;
    if (fin==NULL) {
        err = ZIP_ERRNO;
    }

    if (err == ZIP_OK)
    do {
        err = ZIP_OK;
        size_read = (int)fread(buf,1,size_buf,fin);
        if (size_read < size_buf)
        if (feof(fin)==0) {
            nuzip_printf("error in reading %s\n",filenameinzip);
            err = ZIP_ERRNO;
        }

        if (size_read>0)
            calculate_crc = crc32(calculate_crc,buf,size_read);
        total_read += size_read;

    } while ((err == ZIP_OK) && (size_read>0));

    if (fin)
        fclose(fin);

    *result_crc=calculate_crc;
    nuzip_printf("file %s crc %x\n",filenameinzip,calculate_crc);
    return err;
}

int zip_main(int argc,char *argv[])
{
    int i;
    int opt_overwrite=0;
    int opt_compress_level=Z_DEFAULT_COMPRESSION;
    int zipfilenamearg = 0;
    opt_quiet = 0;
    char filename_try[MAXFILENAME+16];
    int zipok;
    int err=0;
    int size_buf=0;
    void* buf=NULL;
    const char* password=NULL;

    if (argc==0) {
        do_zip_help();
        return 0;
    }
    else {
        for (i=0;i<argc;i++) {
            if ((*argv[i])=='-') {
                const char *p=argv[i]+1;

                while ((*p)!='\0') {
                    char c=*(p++);;
                    if ((c=='q') || (c=='Q'))
                        opt_quiet = 1;
                    if ((c=='o') || (c=='O'))
                        opt_overwrite = 1;
                    if ((c=='a') || (c=='A'))
                        opt_overwrite = 2;
                    if ((c>='0') && (c<='9'))
                        opt_compress_level = c-'0';

                    if (((c=='p') || (c=='P')) && (i+1<argc)) {
                        password=argv[i+1];
                        i++;
                    }
                }
            }
            else
            if (zipfilenamearg == 0)
                zipfilenamearg = i ;
        }
    }

    size_buf = WRITEBUFFERSIZE;
    buf = (void*)malloc(size_buf);
    if (buf==NULL) {
        nuzip_printf("Error allocating memory\n");
        return ZIP_INTERNALERROR;
    }

    if (zipfilenamearg==0)
        zipok=0;
    else {
        int i,len;
        int dot_found=0;

        zipok = 1 ;
        strncpy(filename_try, argv[zipfilenamearg],MAXFILENAME-1);
        /* strncpy doesnt append the trailing NULL, of the string is too long. */
        filename_try[ MAXFILENAME ] = '\0';

        len=(int)strlen(filename_try);
        for (i=0;i<len;i++)
            if (filename_try[i]=='.')
                dot_found=1;

        if (dot_found==0)
            strcat(filename_try,".zip");

        if (opt_overwrite==2) {
            /* if the file don't exist, we not append file */
            if (check_exist_file(filename_try)==0)
                opt_overwrite=1;
        }
        else
        if (opt_overwrite==0)
        if (check_exist_file(filename_try)!=0) {
            char rep=0;
            do {
                char answer[128];
                int ret;
                nuzip_printf("The file %s exists. Overwrite ? [y]es, [n]o, [a]ppend : ",filename_try);
                ret = scanf("%1s",answer);
                if (ret != 1) {
                    exit(EXIT_FAILURE);
                }
                rep = answer[0] ;
                if ((rep>='a') && (rep<='z'))
                    rep -= 0x20;
            }
            while ((rep!='Y') && (rep!='N') && (rep!='A'));
            if (rep=='N')
                zipok = 0;
            if (rep=='A')
                opt_overwrite = 2;
        }
    }

    if (zipok==1) {
        zipFile zf;
        int errclose;

        zf = zipOpen(filename_try,(opt_overwrite==2) ? 2 : 0);

        if (zf == NULL) {
            nuzip_printf("error opening %s\n",filename_try);
            err= ZIP_ERRNO;
        }
        else
            nuzip_printf("creating %s\n",filename_try);

        for (i=zipfilenamearg+1;(i<argc) && (err==ZIP_OK);i++) {
            if (!((((*(argv[i]))=='-') || ((*(argv[i]))=='/')) &&
                ((argv[i][1]=='o') || (argv[i][1]=='O') ||
                (argv[i][1]=='a') || (argv[i][1]=='A') ||
                (argv[i][1]=='p') || (argv[i][1]=='P') ||
                ((argv[i][1]>='0') || (argv[i][1]<='9'))) &&
            (strlen(argv[i]) == 2))) {
                FILE * fin;
                int size_read;
                char* filenameinzip = argv[i];
                zip_fileinfo zi;
                unsigned long crcFile=0;

                zi.tmz_date.tm_sec = zi.tmz_date.tm_min = zi.tmz_date.tm_hour =
                    zi.tmz_date.tm_mday = zi.tmz_date.tm_mon = zi.tmz_date.tm_year = 0;
                zi.dosDate = 0;
                zi.internal_fa = 0;
                zi.external_fa = 0;
                filetime(filenameinzip,&zi.tmz_date,&zi.dosDate);

                /*
                                err = zipOpenNewFileInZip(zf,filenameinzip,&zi,
                                                 NULL,0,NULL,0,NULL / * comment * /,
                                                 (opt_compress_level != 0) ? Z_DEFLATED : 0,
                                                 opt_compress_level);
                */
                if ((password != NULL) && (err==ZIP_OK))
                    err = getFileCrc(filenameinzip,buf,size_buf,&crcFile);

                err = zipOpenNewFileInZip3(zf,filenameinzip,&zi,
                    NULL,0,NULL,0,NULL /* comment*/,
                    (opt_compress_level != 0) ? Z_DEFLATED : 0,
                    opt_compress_level,0,
                /* -MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY, */
                    -MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY,
                    password,crcFile);

                if (err != ZIP_OK)
                    nuzip_printf("error in opening %s in zipfile\n",filenameinzip);
                else {
                    fin = fopen(filenameinzip,"rb");
                    if (fin==NULL) {
                        err=ZIP_ERRNO;
                        nuzip_printf("error in opening %s for reading\n",filenameinzip);
                    }
                }

                if (err == ZIP_OK)
                do {
                    err = ZIP_OK;
                    size_read = (int)fread(buf,1,size_buf,fin);
                    if (size_read < size_buf)
                    if (feof(fin)==0) {
                        nuzip_printf("error in reading %s\n",filenameinzip);
                        err = ZIP_ERRNO;
                    }

                    if (size_read>0) {
                        err = zipWriteInFileInZip (zf,buf,size_read);
                        if (err<0) {
                            nuzip_printf("error in writing %s in the zipfile\n",
                                filenameinzip);
                        }

                    }
                } while ((err == ZIP_OK) && (size_read>0));

                if (fin)
                    fclose(fin);

                if (err<0)
                    err=ZIP_ERRNO;
                else {
                    err = zipCloseFileInZip(zf);
                    if (err!=ZIP_OK)
                        nuzip_printf("error in closing %s in the zipfile\n",
                            filenameinzip);
                }
            }
        }
        errclose = zipClose(zf,NULL);
        if (errclose != ZIP_OK)
            nuzip_printf("error in closing %s\n",filename_try);
    }
    else {
        do_zip_help();
    }

    free(buf);
    return 0;
}
