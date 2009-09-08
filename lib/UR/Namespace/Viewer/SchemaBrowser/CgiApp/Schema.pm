package UR::Namespace::Viewer::SchemaBrowser::CgiApp::Schema;

use strict;
use warnings;

use base 'UR::Namespace::Viewer::SchemaBrowser::CgiApp::Base';

use Class::Inspector;

sub setup {
my($self) = @_;
    $self->start_mode('show_schema_page');
    $self->mode_param('rm');
    $self->run_modes(
            'show_schema_page' => 'show_schema_page',
    );
}



sub show_schema_page {
my($self) = @_;

$DB::single=1;
    my @namespace_names = $self->GetNamespaceNames();
    my $namespace_name = $self->namespace_name;

    $self->tmpl->param(SELECTED_NAMESPACE => $namespace_name);
    $self->tmpl->param(NAMESPACE_NAMES => [ map { { NAMESPACE_NAME => $_,
                                                    SELECTED => ($_ eq $namespace_name),
                                                  } }
                                            @namespace_names
                                           ]);
    
    my $selected_table = $self->request->Env('tablename') || '';

    return $self->tmpl->output() unless ($namespace_name);

    my $namespace = UR::Namespace->get($namespace_name);
    
    my @data_sources = $namespace->get_data_sources();
    my @table_names = map { $_->table_name } UR::DataSource::RDBMS::Table->get(data_source => \@data_sources);

    $self->tmpl->param(SELECTED_TABLE => $selected_table);
    $self->tmpl->param(TABLE_NAMES => [ map { { TABLENAME => $_,
                                                SELECTED => ($_ eq $selected_table),
                                                LINK_PARAMS => join('&', "namespace=$namespace_name",
                                                                         "tablename=$_"),
                                                URL => 'schema.html',
                                             } }       
                                        @table_names
                                      ]);

    return $self->tmpl->output() unless ($selected_table && grep { $_ eq $selected_table} @table_names);

    # FIXME This won't work if there are tables of the same name in different data sources...
    my $tableobj = UR::DataSource::RDBMS::Table->get(data_source => \@data_sources, table_name => $selected_table);
    # FIXME There's a a "bug" in getting class objects by attributes other than the class name.  There's a workaround
    # in the code that lets it work if you also pass in the namespace.  
    my $class_name_for_table = $tableobj->handler_class_name(namespace => $namespace_name);
    $self->tmpl->param(SELECTED_TABLE_CLASS => $class_name_for_table);

    $self->tmpl->param(SELECTED_TABLE_DATASOURCE => $tableobj->data_source);

    my @table_detail;
    my %primary_keys = map { $_ => 1 } $tableobj->primary_key_constraint_column_names;
    foreach my $column_obj ( $tableobj->columns() ) {
        my %properties;
        #my @properties = split(/\s/, $colinfo);
        #my $colname = $properties[0];

        my $property_obj = UR::Object::Property->get(class_name => $class_name_for_table,
                                                      column_name => $column_obj->column_name);
        $properties{'COLUMN'} = $column_obj->column_name;
        $properties{'ACCESSOR'} = $property_obj->property_name;
        $properties{'TYPE'} = sprintf('%s(%d)',$column_obj->data_type || '', $column_obj->data_length || 0);
        $properties{'CONSTRAINTS'} = sprintf('%s %s', $primary_keys{$column_obj->column_name} ? 'PK' : '',
                                                      $column_obj->nullable eq 'N' ? 'NOT NULL' : '');
        $properties{'REMARKS'} = $column_obj->remarks;
          
        # FIXME do any FKs have multiple originating or reference column names?
        if (my @fk_names = $column_obj->fk_constraint_names) {
            $properties{'FK'} = [ map { { R_TABLE => $_->r_table_name,
                                          R_COL => $_->r_column_name,
                                          NAMESPACE => $namespace_name,
                                      }}
                                      UR::DataSource::RDBMS::FkConstraintColumn->get(fk_constraint_name => \@fk_names,
                                                                                     table_name => $selected_table,
                                                                                     column_name => $column_obj->column_name)
                             ];
        } else {
            $properties{'FK'} = [];
        }

        push @table_detail, \%properties;
    }

    $self->tmpl->param(SELECTED_TABLE_DETAIL => [ sort {$a->{'COLUMN'} cmp $b->{'COLUMN'}}
                                                       @table_detail
                                                ]);

    my @ref_fk_info = map { {  NAMESPACE => $namespace_name,
                               FK_TABLE => $_,
                          }} 
                      sort
                      map {$_->table_name()}
                          $tableobj->ref_fk_constraints();

    $self->tmpl->param(REFERRING_TABLES => \@ref_fk_info);

    return $self->tmpl->output();
}


sub _template {
q(
<HTML><HEAD><TITLE>Database Schema<TMPL_IF NAME="SELECTED_TABLE">: <TMPL_VAR NAME="SELECTED_TABLE"></TMPL_IF></TITLE></HEAD>
<BODY>
<TABLE border=0>
<TR><TD>
        <FORM method="GET">
            Namespace: <SELECT name="namespace">
                <TMPL_LOOP NAME=NAMESPACE_NAMES>
                    <OPTION <TMPL_IF NAME="SELECTED">selected</TMPL_IF>
                            label="<TMPL_VAR ESCAPE=HTML NAME="NAMESPACE_NAME">"
                            value="<TMPL_VAR ESCAPE=HTML NAME="NAMESPACE_NAME">" >
                        <TMPL_VAR NAME="NAMESPACE_NAME">
                     </OPTION>
                </TMPL_LOOP>
                <TMPL_UNLESS NAME="SELECTED_NAMESPACE">
                    <OPTION>Please select a namespace</OPTION>
                </TMPL_UNLESS>
            </SELECT><BR>
            Table: <INPUT TYPE=text name="tablename"><BR>
            <INPUT type="submit" name="Go" value="Go">
        </FORM>
</TD></TR>
<TR><TD>
        <TABLE border=1>
            <TR><TD width="20%">

                    <! The list of DB table names on the left>

                    <TMPL_IF NAME="SELECTED_NAMESPACE">
                        <TABLE border=0>
                            <TMPL_LOOP NAME="TABLE_NAMES">
                                <TR><TD align=left>
                                        <TMPL_IF NAME="SELECTED">
                                            <TMPL_VAR ESCAPE=HTML NAME="TABLENAME">
                                        <TMPL_ELSE>
                                            <A HREF="<TMPL_VAR NAME="URL">?<TMPL_VAR NAME="LINK_PARAMS">">
                                                 <TMPL_VAR ESCAPE=HTML NAME="TABLENAME">
                                            </A>
                                        </TMPL_IF>
                                </TD></TR>
                            </TMPL_LOOP>
                        </TABLE>
                    </TMPL_IF>
            </TD>
            <TD valign=top>
                <TABLE border=0>
                    <TR><TD><H2><TMPL_VAR NAME="SELECTED_TABLE"></H2></TD>
                        <TD><TMPL_IF NAME="SELECTED_TABLE_CLASS">
                                <A HREF="class.html?namespace=<TMPL_VAR NAME="SELECTED_NAMESPACE">&classname=<TMPL_VAR NAME="SELECTED_TABLE_CLASS">">Class <TMPL_VAR NAME="SELECTED_TABLE_CLASS"></A>
                            <TMPL_ELSE>
                                 No related class
                            </TMPL_IF>
                        </TD>
                    </TR>
                    <TR><TD>
                            Data Source: <TMPL_VAR NAME="SELECTED_TABLE_DATASOURCE">
                        </TD>
                    </TR>
                </TABLE>

                <TABLE border=1>
                    <TR><TH>Column</TH><TH>Accessor</TH><TH>Type</TH><TH>Constraints</TH><TH>Foreign Key To</TH></TR>
                    <TMPL_LOOP NAME="SELECTED_TABLE_DETAIL">
                        <TR><TD>&nbsp <TMPL_VAR NAME="COLUMN"></TD>
                            <TD> <TMPL_VAR NAME="ACCESSOR"></TD>
                            <TD> <TMPL_VAR NAME="TYPE"></TD>
                            <TD>&nbsp <TMPL_VAR NAME="CONSTRAINTS"></TD>
                            <TD>&nbsp
                                <TMPL_LOOP NAME="FK">
                                    <A HREF="schema.html?namespace=<TMPL_VAR NAME="NAMESPACE">&tablename=<TMPL_VAR NAME="R_TABLE">"><TMPL_VAR NAME="R_TABLE"></A>.<TMPL_VAR NAME="R_COL">
                                    <BR>
                                </TMPL_LOOP>
                            </TD>
                        </TR>
                    </TMPL_LOOP>
                </TABLE>

                <TABLE border=0>
                    <TR><TH>Referring tables</TH></TR>
                    <TMPL_LOOP NAME="REFERRING_TABLES">
                        <TR><TD>
                              <A HREF="schema.html?namespace=<TMPL_VAR NAME="NAMESPACE">&tablename=<TMPL_VAR NAME="FK_TABLE">"><TMPL_VAR NAME="FK_TABLE"></A>
                            </TD>
                        </TR>
                    </TMPL_LOOP>
                </TABLE>

            </TD></TR>
        </TABLE>
</TD></TR>
</TABLE>
</BODY>

)};

1;
